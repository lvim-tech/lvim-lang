-- lvim-lang.providers.erlang: the Erlang provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Reuses the shared core: the
-- per-filetype catalog (core.catalog), the LSP fan-out (core.lsp.register_catalog), the lvim-tasks
-- runner (core.runner) and on-demand tooling (core.ensure).
--
-- erlang_ls (the erlang-ls language server, mason package `erlang-ls` / binary `erlang_ls`) is the
-- single Erlang server; it does not format Erlang, so the per-filetype formatter defaults to
-- **erlfmt** through efm (format-on-save), and `catalog.lsp_on_attach` switches the LSP's formatting
-- capability off on attach so the two never both format the buffer. erlang_ls provides diagnostics
-- (compiler + dialyzer), so the efm linter defaults to `false`. build / test go through **rebar3**
-- (compile / shell / eunit / ct) — the standard Erlang build tool. Erlang has NO reliable mason debug
-- adapter (erlang_ls' own debugging is limited), so NO debugger is declared — see the OPEN note in
-- docs/providers/erlang.md.
--
---@module "lvim-lang.providers.erlang"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.providers.erlang.toolchain")
local core_toolchain = require("lvim-lang.core.toolchain")
local requirements = require("lvim-lang.core.requirements")

---@type table
local DEFAULTS = {
    -- Explicit binary paths; when set each wins over every other resolution strategy.
    erl_path = nil,
    rebar3_path = nil,
    erlang_ls_path = nil,
    erlfmt_path = nil,
    -- A shell command whose first output line is the `erl` binary path (checked after erl_path,
    -- before the version manager / PATH). Empty by default.
    erl_lookup_cmd = nil,
    -- Version manager for the runtime: "mise" | "asdf" | false (ignore) | function(root). Honours the
    -- project's pin (.tool-versions). Default: try mise, then asdf (each `<mgr> which erl`), else PATH.
    -- kerl-managed installs are found on PATH (kerl is a shell installer with no resolver CLI).
    version_manager = nil,

    -- LSP server catalog. erlang_ls is the single Erlang server; the mason package is `erlang-ls`
    -- and the binary is `erlang_ls`. Its project configuration lives in an `erlang_ls.config` file at
    -- the project root (not pushed over the protocol), so `settings` is empty by default.
    lsp = {
        servers = {
            ["erlang-ls"] = {
                mason = "erlang-ls",
                bin = "erlang_ls", -- the installed binary name differs from the mason package name
                filetypes = { "erlang" },
                role = "types", -- completion / hover / definition / references / diagnostics
                settings = {},
            },
        },
        default = "erlang-ls",
    },

    -- Per-FILETYPE catalog: the formatter / linter / debugger for `erlang`, each with a default
    -- config, plus which is the `default` (or false = none). erlang_ls does NOT format Erlang, so
    -- **erlfmt** is the default formatter (through efm, reading stdin / emitting stdout). erlang_ls
    -- provides diagnostics, so the linter defaults to `false` (the catalog carries none). Erlang has
    -- no reliable mason debug adapter, so `debuggers` is empty and the default debugger is `false`.
    ft = {
        erlang = {
            formatters = {
                -- erlfmt reads the buffer on stdin and emits the formatted source to stdout.
                erlfmt = { mason = "erlfmt", efm = { formatCommand = "erlfmt -", formatStdin = true } },
            },
            linters = {},
            debuggers = {},
            defaults = { formatter = "erlfmt", linter = false, debugger = false },
        },
    },

    -- Nerd Font icons used in the Erlang provider's statusline / pickers (all configurable).
    icons = {
        statusline = "", -- the Erlang marker in the statusline segment (nf-dev-erlang, U+E7B1)
        test = "󰙨", -- test runner / result row
        build = "󰜫", -- build task row
        run = "󰐊", -- run task row
        deps = "󰏗", -- dependency row
    },
}

--- Health section for :checkhealth lvim-lang: whether the Erlang toolchain (erl + rebar3 + erlang_ls
--- + erlfmt) resolves for the current working directory, and at what version.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."

    local erl, reason = core_toolchain.resolve("erlang", "erl", root)
    if erl then
        local ver = core_toolchain.version("erlang", "erl", root)
        h.ok(("erl: %s%s"):format(erl, ver and ("  (" .. ver .. ")") or ""))
    else
        h.warn(
            ("erl not found — %s"):format(
                reason or "install Erlang/OTP (mise / asdf / kerl) or set providers.erlang.erl_path"
            )
        )
    end

    local rebar3, rreason = core_toolchain.resolve("erlang", "rebar3", root)
    if rebar3 then
        local ver = core_toolchain.version("erlang", "rebar3", root)
        h.ok(("rebar3: %s%s"):format(rebar3, ver and ("  (" .. ver .. ")") or ""))
    else
        h.warn(
            ("rebar3 not found — %s"):format(rreason or "install rebar3 (the Erlang build tool) and put it on PATH")
        )
    end

    for _, tool in ipairs({ "erlang_ls", "erlfmt" }) do
        local path = core_toolchain.resolve("erlang", tool, root)
        if path then
            h.ok(("%s: %s"):format(tool, path))
        else
            h.info(("%s not found — installed on demand from the mason registry"):format(tool))
        end
    end
end

--- Statusline segment for a root: the Erlang marker + the active run config (if any).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.erlang and config.providers.erlang.icons) or {}
    local parts = { ic.statusline or "" }
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
    name = "erlang",
    filetypes = { "erlang" },
    root_patterns = { "rebar.config", "erlang.mk", ".git" },
    statusline = statusline,
    toolchain = toolchain,
    commands = require("lvim-lang.providers.erlang.commands"),
    -- lvim-tasks templates (arg-less rebar3 dependency subcommands) — also via :LvimLang deps.
    tasks = require("lvim-lang.providers.erlang.deps").templates,
    --- Surfaced at activation + in :checkhealth: Erlang/OTP (`erl`) and the rebar3 build tool must be
    --- present (erlang_ls needs the runtime; build / test need rebar3). Erlang is the user's OWN runtime.
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
        return {
            requirements.tool_present(
                "erlang",
                "erl",
                "Erlang/OTP runtime",
                "Install Erlang/OTP via a version manager (mise / asdf / kerl) and put `erl` on PATH, or "
                    .. "set providers.erlang.erl_path; the language server needs it.",
                root
            ),
            requirements.tool_present(
                "erlang",
                "rebar3",
                "rebar3 build tool",
                "Install rebar3 (the Erlang build tool) and put it on PATH, vendor it at the project root, "
                    .. "or set providers.erlang.rebar3_path; build / test commands need it.",
                root
            ),
        }
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
