-- lvim-lang.providers.swift: the Swift provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes/root, the sourcekit-lsp catalog, the per-filetype tool catalog (swiftformat / swiftlint
-- / lldb-dap+codelldb), the toolchain resolution, requirements, health and statusline — and this module
-- then EXTENDS the returned spec with the two things pure data cannot express, plus Swift's idiosyncratic
-- command surface:
--   (1) the `swift` compiler resolves through a user LOOKUP command (swiftly) between the explicit path
--       and the version manager;
--   (2) sourcekit-lsp AND the toolchain's own lldb-dap ship INSIDE the Swift toolchain (beside `swift`,
--       no mason package) — exactly like dartls ships with the Dart SDK;
--   (3) the one-shot `swift` CLI tasks (build/run/test/clean/fmt), the SwiftPM dependency commands, the
--       XCTest-under-cursor runner and lldb debugging (providers.swift.commands / .dap / .tasks / .deps).
--
-- The reusable strategy builders (explicit / mason / PATH) come from core.detect; only the Swift-specific
-- seams (lookup, beside-swift) live here. servers/sourcekit-lsp.lua stays a bespoke server-config module
-- (it resolves the SDK-bundled binary per root and registers the lldb DAP) — a real file on disk always
-- wins over the factory's generic shim.
--
---@module "lvim-lang.providers.swift"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")
local detect = require("lvim-lang.core.detect")
local core_toolchain = require("lvim-lang.core.toolchain")

-- Per-language defaults, seeded into config.providers.swift at registration (users override via
-- setup({ providers = { swift = { … } } })). Explicit binary overrides live under `bin_paths` (the
-- shared key across every provider); `version_manager` / `swift_lookup_cmd` tune resolution.
---@type LvimLangSpecData
local DATA = {
    name = "swift",
    filetypes = { "swift" },
    root_patterns = { "Package.swift", ".git" },

    -- The Swift compiler/package driver is the user's own toolchain (Xcode / swiftly / a Linux
    -- tarball) — surfaced as a requirement, resolved (never installed) by the toolchain below.
    runtime = {
        bin = "swift",
        key = "swift",
        label = "Swift toolchain",
        hint = "Install the Swift toolchain (Xcode on macOS, swiftly or a Linux toolchain on PATH); "
            .. "sourcekit-lsp ships with it, beside `swift`.",
        severity = "warn",
    },

    -- LSP catalog. sourcekit-lsp is the default; it ships WITH the toolchain, so it carries NO mason
    -- package (`mason` absent) — the extend below adds its "beside swift" resolution. settings /
    -- init_options pass straight through and are overridable via setup().
    lsp = {
        servers = {
            ["sourcekit-lsp"] = {
                filetypes = { "swift" },
                role = "types", -- completion / hover / definition / rename / format / diagnostics
                settings = {},
                init_options = {},
            },
        },
        default = "sourcekit-lsp",
    },

    -- Per-filetype catalog. swiftformat (efm) is the default formatter → on attach sourcekit-lsp's own
    -- formatting is disabled and swiftformat owns it; swiftlint is an opt-in linter; lldb-dap the
    -- default debugger (codelldb an alternative).
    ft = {
        swift = {
            formatters = {
                swiftformat = {
                    mason = "swiftformat",
                    efm = { formatCommand = "swiftformat --quiet", formatStdin = true },
                },
            },
            linters = {
                swiftlint = {
                    mason = "swiftlint",
                    efm = {
                        lintCommand = "swiftlint lint --quiet ${INPUT}",
                        lintStdin = false,
                        lintFormats = { "%f:%l:%c: %t%*[^:]: %m" },
                        rootMarkers = { ".swiftlint.yml", ".swiftlint.yaml" },
                    },
                },
            },
            debuggers = {
                ["lldb-dap"] = { mason = "lldb-dap" },
                codelldb = { mason = "codelldb" },
            },
            defaults = { formatter = "swiftformat", linter = false, debugger = "lldb-dap" },
        },
    },

    -- Statusline / picker icons (Nerd Font, all configurable).
    icons = {
        statusline = "", -- the Swift marker in the statusline segment (nf-seti-swift, U+E755)
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗", -- SwiftPM dependency row
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND: the two toolchain shapes pure data cannot express ──────────────────────────────────────

--- The swift config block (seeded above).
---@return table
local function opts()
    return config.providers.swift or {}
end

--- Run the user's `swift_lookup_cmd` and take its first non-empty line as the swift path (the seam for
--- swiftly and other managers that print a resolved binary path — e.g. `swiftly use --print-location`).
---@return string|nil
local function lookup_swift()
    local cmd = opts().swift_lookup_cmd
    if type(cmd) ~= "string" or cmd == "" then
        return nil
    end
    local out = vim.fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 or type(out) ~= "table" then
        return nil
    end
    for _, line in ipairs(out) do
        local trimmed = vim.trim(line)
        if trimmed ~= "" then
            return trimmed
        end
    end
    return nil
end

--- The `bin` that sits beside the resolved `swift` in the same toolchain bin dir (sourcekit-lsp and the
--- toolchain's own lldb both live there), or nil.
---@param bin string  "sourcekit-lsp" | "lldb-dap"
---@return fun(root: string): string|nil
local function beside_swift(bin)
    return function(root)
        local swift = core_toolchain.resolve("swift", "swift", root)
        if not swift then
            return nil
        end
        local path = vim.fs.joinpath(vim.fs.dirname(swift), bin)
        return vim.fn.executable(path) == 1 and path or nil
    end
end

local tc = spec.toolchain.tools
-- swift: explicit → LOOKUP cmd → version manager → PATH (insert the lookup seam after the explicit path).
table.insert(tc.swift, 2, { kind = "path", value = lookup_swift })
-- sourcekit-lsp ships with the toolchain (no mason → the base added no strategy): explicit → beside → PATH.
tc["sourcekit-lsp"] = {
    { kind = "path", value = detect.explicit("swift", "sourcekit-lsp") },
    { kind = "path", value = beside_swift("sourcekit-lsp") },
    { kind = "which", value = "sourcekit-lsp" },
}
-- lldb-dap: fall back to the toolchain's own before PATH (base gives explicit → mason → PATH).
table.insert(tc["lldb-dap"], #tc["lldb-dap"], { kind = "path", value = beside_swift("lldb-dap") })

-- ── EXTEND: the idiosyncratic command surface (adaptive CLI, SwiftPM deps, lldb, test-under-cursor) ──
spec.commands = require("lvim-lang.providers.swift.commands")
-- lvim-tasks templates (arg-less SwiftPM dependency subcommands) — also via :LvimLang deps.
spec.tasks = require("lvim-lang.providers.swift.deps").templates

registry.register(spec, defaults)

return spec
