-- lvim-lang.providers.swift: the Swift provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Wires the toolchain
-- (swift/sourcekit-lsp/swiftformat/lldb-dap), the sourcekit-lsp LSP catalog, the one-shot `swift`
-- CLI tasks (build/run/test/clean/fmt), the SwiftPM dependency commands, lldb debugging, a health
-- section and a statusline segment.
--
-- Reuses the shared core: the canonical per-filetype catalog (core.catalog), the multi-LSP fan-out
-- (core.lsp.register_catalog) and the requirements surface. sourcekit-lsp SHIPS WITH the Swift
-- toolchain (like dartls with the Dart SDK), so it carries NO mason package — presence is the
-- toolchain's / health's concern. The default formatter is swiftformat via efm (sourcekit-lsp can
-- also format, but the catalog default hands formatting to swiftformat); swiftlint is an opt-in
-- linter (sourcekit-lsp provides diagnostics by default).
--
---@module "lvim-lang.providers.swift"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.providers.swift.toolchain")
local core_toolchain = require("lvim-lang.core.toolchain")
local requirements = require("lvim-lang.core.requirements")

-- Per-language defaults, merged into config.providers.swift at registration (users override via
-- setup({ providers = { swift = { … } } })).
---@type table
local DEFAULTS = {
    -- Explicit binary paths; each wins over every other resolution strategy.
    swift_path = nil,
    sourcekit_lsp_path = nil,
    swiftformat_path = nil,
    lldb_dap_path = nil,
    codelldb_path = nil,
    -- A shell command whose first non-empty line is the `swift` binary path (checked after
    -- swift_path, before the version manager / PATH) — the seam for swiftly and friends. Empty by default.
    swift_lookup_cmd = nil,
    -- Version manager for the `swift` toolchain: "mise" | "asdf" | false (ignore) | function(root).
    -- Honours the project's pinned Swift version. Default: try mise then asdf, else PATH. (swiftly,
    -- which has no `which` verb, is wired through swift_lookup_cmd or a function instead.)
    version_manager = nil,

    -- LSP server catalog. sourcekit-lsp is the default; it ships with the Swift toolchain, so it has
    -- NO mason package (`mason` absent) — presence is the toolchain's / health's concern. `default`
    -- may be a STRING or a LIST (multi-LSP). settings / init_options pass straight through.
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

    -- Per-filetype catalog. sourcekit-lsp attaches to `swift`; the default formatter is swiftformat
    -- (efm), so on attach sourcekit-lsp's own formatting is disabled and swiftformat owns it. swiftlint
    -- is an opt-in linter (set ft.swift.linter = "swiftlint"); the default debugger is lldb-dap.
    ft = {
        swift = {
            formatters = {
                -- swiftformat reads the buffer from stdin (no path arg) and writes the formatted
                -- source to stdout — exactly what efm's formatStdin expects.
                swiftformat = {
                    mason = "swiftformat",
                    efm = { formatCommand = "swiftformat --quiet", formatStdin = true },
                },
            },
            linters = {
                swiftlint = {
                    mason = "swiftlint",
                    -- swiftlint's default reporter prints `file:line:col: warning|error: message (rule)`.
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
            -- swiftformat formats via efm; sourcekit-lsp provides diagnostics, so no default linter.
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

--- Health section for :checkhealth lvim-lang: report whether the Swift toolchain resolves for the
--- current working directory, and at what version.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."
    for _, tool in ipairs({ "swift", "sourcekit-lsp", "swiftformat", "lldb-dap" }) do
        local path, reason = core_toolchain.resolve("swift", tool, root)
        local ver = path and core_toolchain.version("swift", tool, root) or nil
        if path then
            h.ok(("%s: %s%s"):format(tool, path, ver and ("  (" .. ver .. ")") or ""))
        elseif tool == "swift" then
            h.warn(
                ("swift not found — %s"):format(
                    reason or "install the Swift toolchain (Xcode / swiftly / a Linux toolchain on PATH)"
                )
            )
        elseif tool == "sourcekit-lsp" then
            h.warn(
                "sourcekit-lsp not found — it ships with the Swift toolchain; install Swift and put its bin dir on PATH"
            )
        else
            h.info(("%s not found — installed on demand from the mason registry"):format(tool))
        end
    end
end

--- Statusline segment for a root: the Swift marker + the active run config (if any).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.swift and config.providers.swift.icons) or {}
    local parts = { ic.statusline or "" }
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
    name = "swift",
    filetypes = { "swift" },
    root_patterns = { "Package.swift", ".git" },
    statusline = statusline,
    toolchain = toolchain,
    commands = require("lvim-lang.providers.swift.commands"),
    -- lvim-tasks templates (arg-less SwiftPM dependency subcommands) — also via :LvimLang deps.
    tasks = require("lvim-lang.providers.swift.deps").templates,
    --- Surfaced at activation + in :checkhealth: the Swift toolchain must be present (sourcekit-lsp
    --- ships inside it).
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
        return {
            requirements.tool_present(
                "swift",
                "swift",
                "Swift toolchain",
                "Install the Swift toolchain (Xcode on macOS, swiftly or a Linux toolchain on PATH); "
                    .. "sourcekit-lsp ships with it, beside `swift`.",
                root
            ),
        }
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
