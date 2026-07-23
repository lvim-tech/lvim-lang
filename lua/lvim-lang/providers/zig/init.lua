-- lvim-lang.providers.zig: the Zig provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Zig is a compiled systems language
-- served by ONE self-contained binary: `zig` is the compiler, build system (`zig build`), test
-- runner (`zig test` / `zig build test`) AND formatter (`zig fmt` — a subcommand, NOT a separate
-- tool). The LSP is zls; debugging is lldb-dap (LLVM's DAP adapter over the native DWARF binaries).
--
-- Reuses the Rust/C++ core: the canonical per-filetype catalog (core.catalog), the multi-LSP fan-out
-- (core.lsp.register_catalog) and on-demand tooling (core.ensure). Because zls formats natively (it
-- shells out to `zig fmt`) the default formatter is `false` — formatting comes from the LSP; `zig
-- fmt` is still OFFERED as an efm formatter a user can select. There is no default linter (zls
-- surfaces compile diagnostics). The Zig toolchain itself is the user's own (via mise / asdf / PATH);
-- only zls and lldb-dap are mason packages.
--
---@module "lvim-lang.providers.zig"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.providers.zig.toolchain")
local core_toolchain = require("lvim-lang.core.toolchain")
local requirements = require("lvim-lang.core.requirements")

---@type table
local DEFAULTS = {
    -- Explicit binary paths; each wins over every other resolution strategy.
    zig_path = nil,
    zls_path = nil,
    lldb_dap_path = nil,
    codelldb_path = nil,
    zig_lookup_cmd = nil, -- shell command whose first line is the `zig` path
    -- Version manager for the toolchain: "mise" | "asdf" | false | function(root).
    -- Honours a project's .tool-versions / mise.toml. Default: mise → asdf → PATH.
    version_manager = nil,

    -- The Zig build output dir (relative to the project root), where `zig build` drops binaries.
    -- Used to default the debugger's "path to executable" prompt.
    bin_dir = "zig-out/bin",

    -- LSP server catalog. zls is the single server. It formats Zig natively (it invokes `zig fmt`)
    -- and surfaces compile diagnostics, so no separate efm formatter/linter runs by default.
    lsp = {
        servers = {
            zls = {
                mason = "zls",
                filetypes = { "zig" },
                role = "types", -- completion / hover / definition / rename / inlay hints / format
                -- zls is configured through workspace settings under the `zls` key (pushed after init
                -- via didChangeConfiguration). Overridable / extendable via setup().
                settings = {
                    zls = {
                        enable_build_on_save = true, -- run `zig build` on save for richer diagnostics
                        semantic_tokens = "full",
                        inlay_hints_show_parameter_name = true,
                        inlay_hints_show_builtin = true,
                        warn_style = true,
                    },
                },
            },
        },
        default = "zls",
    },

    -- Per-filetype catalog. `zig fmt` is offered as an efm formatter (opt-in — zls formats by
    -- default). lldb-dap is the default debugger; codelldb is an alternative.
    ft = {
        zig = {
            formatters = {
                -- The formatter ships inside the `zig` binary. `zig fmt --stdin` reads stdin and
                -- writes the formatted source to stdout (efm's format contract).
                ["zig-fmt"] = { efm = { formatCommand = "zig fmt --stdin", formatStdin = true } },
            },
            linters = {},
            debuggers = {
                ["lldb-dap"] = { mason = "lldb-dap" },
                codelldb = { mason = "codelldb" },
            },
            -- zls formats (via `zig fmt`) and lints (compile diagnostics), so formatter/linter default
            -- to false; lldb-dap is the default debugger.
            defaults = { formatter = false, linter = false, debugger = "lldb-dap" },
        },
    },

    -- Statusline / picker icons (Nerd Font, single-width, all configurable).
    icons = {
        statusline = "", -- the Zig marker in the statusline segment
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗", -- build.zig.zon dependency row
    },
}

--- Health section for :checkhealth lvim-lang: report whether the Zig toolchain resolves for the
--- current working directory, and at what version.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."
    local report = {
        {
            tool = "zig",
            level = "warn",
            hint = "install the Zig toolchain (https://ziglang.org/download) and put `zig` on PATH (or via mise / asdf)",
        },
        {
            tool = "zls",
            level = "info",
            hint = "install it via the mason registry (:LvimInstaller) — the Zig language server",
        },
        { tool = "lldb-dap", level = "info", hint = "the mason registry — the LLDB debug adapter (or codelldb)" },
    }
    for _, r in ipairs(report) do
        local path = core_toolchain.resolve("zig", r.tool, root)
        if path then
            local ver = core_toolchain.version("zig", r.tool, root)
            h.ok(("%s: %s%s"):format(r.tool, path, ver and ("  (" .. ver .. ")") or ""))
        elseif r.level == "warn" then
            h.warn(("%s not found — %s"):format(r.tool, r.hint))
        else
            h.info(("%s not found — %s"):format(r.tool, r.hint))
        end
    end
end

--- Statusline segment for a root: the Zig marker + the active run config (if any).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.zig and config.providers.zig.icons) or {}
    local parts = { ic.statusline or "" }
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
    name = "zig",
    filetypes = { "zig", "zir" },
    root_patterns = { "build.zig", "build.zig.zon", ".git" },
    statusline = statusline,
    toolchain = toolchain,
    commands = require("lvim-lang.providers.zig.commands"),
    -- lvim-tasks templates (arg-less package commands) — also via :LvimLang deps.
    tasks = require("lvim-lang.providers.zig.deps").templates,
    --- Surfaced at activation + in :checkhealth: the Zig toolchain must be present (zls needs it to
    --- resolve the standard library, build, format and produce diagnostics).
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
        return {
            requirements.tool_present(
                "zig",
                "zig",
                "Zig toolchain",
                "Install the Zig toolchain (https://ziglang.org/download) and put `zig` on PATH (or manage it "
                    .. "with mise / asdf). `zig fmt` ships with it; zls resolves the standard library through it.",
                root
            ),
        }
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
