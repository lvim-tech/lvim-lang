-- lvim-lang.providers.elixir: the Elixir provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Reuses the shared core: the
-- per-filetype catalog (core.catalog), the multi-LSP fan-out (core.lsp.register_catalog), the
-- lvim-tasks runner (core.runner) and on-demand tooling (core.ensure).
--
-- elixir-ls (the ElixirLS language server) is the default; lexical and next-ls are offered as
-- alternatives. All three are mason packages resolved per project. elixir-ls formats natively (it
-- drives `mix format`) and reports credo/dialyzer diagnostics, so the per-filetype efm formatter /
-- linter default to `false` (the LSP owns them); the catalog still OFFERS `mix format` (formatter) and
-- credo (linter) through efm for users who prefer efm-based tooling — and `catalog.lsp_on_attach`
-- hands formatting to efm whenever such a formatter IS selected, so the two never both format the
-- buffer. Debugging rides on the elixir-ls DEBUGGER (a second binary in the elixir-ls mason package),
-- wired in providers.elixir.dap and carried on every server config's `dap` field so it works whichever
-- LSP is chosen. build = `mix compile`; run = `mix run` / `iex -S mix`; ExUnit drives the tests.
--
---@module "lvim-lang.providers.elixir"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.providers.elixir.toolchain")
local core_toolchain = require("lvim-lang.core.toolchain")
local requirements = require("lvim-lang.core.requirements")

---@type table
local DEFAULTS = {
    -- Explicit binary paths; when set each wins over every other resolution strategy.
    elixir_path = nil,
    mix_path = nil,
    elixir_ls_path = nil,
    elixir_ls_debugger_path = nil,
    -- A shell command whose first output line is the `elixir` binary path (checked after elixir_path,
    -- before the version manager / PATH). Empty by default.
    elixir_lookup_cmd = nil,
    -- Version manager for the runtime: "mise" | "asdf" | false (ignore) | function(root, tool).
    -- Honours the project's pin (.tool-versions). Default: try mise then asdf (`<mgr> which <tool>`).
    version_manager = nil,

    -- Debug adapter tuning.
    dap = {
        -- The files the elixir-ls debugger compiles before an ExUnit `test` task runs.
        test_require_files = { "test/**/test_helper.exs", "test/**/*_test.exs" },
    },

    -- LSP server catalog. elixir-ls is the default; lexical and next-ls are offered as alternatives —
    -- set `lsp.server = "lexical"` (or a list) to switch / add. `role` coordinates overlaps.
    lsp = {
        servers = {
            ["elixir-ls"] = {
                mason = "elixir-ls",
                bin = "elixir-ls",
                filetypes = { "elixir", "eelixir", "heex" },
                role = "types", -- completion / hover / definition / rename / format / diagnostics
                -- elixir-ls reads its options from settings under the `elixirLS` key (pushed after
                -- init) AND init_options (available at startup); the server module injects them per root.
                settings = {
                    elixirLS = {
                        dialyzerEnabled = true, -- run dialyzer for extra type diagnostics
                        dialyzerFormat = "dialyxir_long",
                        fetchDeps = false, -- do NOT auto-fetch deps on open (run :LvimLang deps get)
                        enableTestLenses = false,
                        suggestSpecs = true,
                        mixEnv = "test", -- the MIX_ENV elixir-ls compiles under
                        autoInsertRequiredAlias = true,
                    },
                },
            },
            lexical = {
                mason = "lexical",
                bin = "lexical",
                filetypes = { "elixir", "eelixir", "heex" },
                role = "types", -- alternative full server (completion / hover / definition / format)
                settings = {},
            },
            ["next-ls"] = {
                mason = "next-ls",
                bin = "nextls",
                filetypes = { "elixir", "eelixir", "heex" },
                role = "types", -- alternative full server (elixir-tools' Next LS)
                settings = {},
            },
        },
        default = "elixir-ls",
    },

    -- Per-FILETYPE catalog: formatters / linters for `elixir`, each with an efm config, plus which is
    -- the `default` (or false = none). elixir-ls formats (via `mix format`) + diagnoses natively, so
    -- both default to `false`; the catalog still OFFERS `mix format` and credo through efm for users
    -- who prefer efm-based tooling (set ft.elixir.formatter = "mix_format", ft.elixir.linter =
    -- "credo"). The elixir-ls DEBUGGER is a mason package (offered for install), wired in
    -- providers.elixir.dap and carried on the server config.
    ft = {
        elixir = {
            formatters = {
                -- `mix format -` reads stdin and writes the formatted source to stdout (Elixir 1.13+),
                -- honouring the project's `.formatter.exs`.
                mix_format = {
                    efm = {
                        formatCommand = "mix format -",
                        formatStdin = true,
                        rootMarkers = { "mix.exs", ".formatter.exs" },
                    },
                },
            },
            linters = {
                -- credo's flycheck format is `path:line:col: category: message`; run over stdin so an
                -- unsaved buffer still lints. Needs the `credo` dependency in the project's mix.exs.
                credo = {
                    efm = {
                        lintCommand = "mix credo suggest --format=flycheck --read-from-stdin ${INPUT}",
                        lintStdin = true,
                        lintFormats = { "%f:%l:%c: %t: %m", "%f:%l: %t: %m" },
                        rootMarkers = { "mix.exs", ".credo.exs" },
                    },
                },
            },
            debuggers = {
                -- The elixir-ls debug adapter ships as a second binary in the elixir-ls mason package.
                ["elixir-ls"] = { mason = "elixir-ls", bin = "elixir-ls-debugger" },
            },
            defaults = { formatter = false, linter = false, debugger = "elixir-ls" },
        },
    },

    -- Nerd Font icons used in the Elixir provider's statusline / pickers (all configurable).
    icons = {
        statusline = "", -- the Elixir marker in the statusline segment (nf-seti-elixir)
        test = "󰙨", -- test runner / result row
        build = "󰜫", -- mix compile / build task row
        run = "󰐊", -- run task row
        debug = "󰃤", -- debug session row
        deps = "󰏗", -- hex / mix dependency row
    },
}

--- Health section for :checkhealth lvim-lang: whether the Elixir toolchain (runtime + servers +
--- debugger) resolves for the current working directory, and at what version.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."

    local elixir, reason = core_toolchain.resolve("elixir", "elixir", root)
    if elixir then
        local ver = core_toolchain.version("elixir", "elixir", root)
        h.ok(("elixir: %s%s"):format(elixir, ver and ("  (" .. ver .. ")") or ""))
    else
        h.warn(
            ("elixir not found — %s"):format(
                reason or "install Elixir (mise / asdf) or set providers.elixir.elixir_path"
            )
        )
    end

    -- mix + iex ship with elixir; the language servers / debugger are mason packages resolved on demand.
    for _, tool in ipairs({ "mix", "iex" }) do
        local path = core_toolchain.resolve("elixir", tool, root)
        if path then
            local ver = core_toolchain.version("elixir", tool, root)
            h.ok(("%s: %s%s"):format(tool, path, ver and ("  (" .. ver .. ")") or ""))
        else
            h.info(("%s not found — ships with elixir; install the Elixir runtime"):format(tool))
        end
    end

    for _, tool in ipairs({ "elixir-ls", "lexical", "nextls" }) do
        local path = core_toolchain.resolve("elixir", tool, root)
        if path then
            h.ok(("%s: %s"):format(tool, path))
        else
            h.info(("%s not found — installed on demand from the mason registry"):format(tool))
        end
    end

    if core_toolchain.resolve("elixir", "elixir-ls-debugger", root) then
        h.ok("elixir-ls-debugger: present (the elixir-ls mason package's debug adapter)")
    else
        h.info("elixir-ls-debugger not found — installed with the elixir-ls mason package (debugging)")
    end
end

--- Statusline segment for a root: the Elixir marker + the active run config (if any).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.elixir and config.providers.elixir.icons) or {}
    local parts = { ic.statusline or "" }
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
    name = "elixir",
    filetypes = { "elixir", "eelixir", "heex" },
    root_patterns = { "mix.exs", ".git" },
    statusline = statusline,
    toolchain = toolchain,
    commands = require("lvim-lang.providers.elixir.commands"),
    -- lvim-tasks templates (arg-less mix dependency subcommands) — also via :LvimLang deps.
    tasks = require("lvim-lang.providers.elixir.deps").templates,
    --- Surfaced at activation + in :checkhealth: an Elixir runtime must be present (the language
    --- server, mix tasks and ExUnit all run on it). Elixir is the user's OWN runtime — not
    --- lvim-pkg-installed.
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
        return {
            requirements.tool_present(
                "elixir",
                "elixir",
                "Elixir runtime",
                "Install Elixir via a version manager (mise / asdf) and pin it with .tool-versions, or set "
                    .. "providers.elixir.elixir_path; the language server, mix tasks and ExUnit all need it.",
                root
            ),
        }
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
