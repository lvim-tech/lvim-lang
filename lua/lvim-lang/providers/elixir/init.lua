-- lvim-lang.providers.elixir: the Elixir provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes/root, the elixir-ls (default) + lexical + next-ls LSP catalog, the per-filetype tool
-- catalog (mix format / credo over efm, the elixir-ls debugger), the elixir toolchain, the requirement,
-- health and statusline. This module then EXTENDS the returned spec with Elixir's idiosyncratic parts:
--   * mix / iex resolved from the SELECTED elixir's bin dir (tracking a version-managed install);
--   * the elixir-ls-debugger binary (a second binary inside the elixir-ls mason package);
--   * a bin-keyed alias (next-ls' server module resolves by the BINARY `nextls`, not the catalog key);
--   * the dap tuning + the mix build/run/test command surface (providers.elixir.commands / .dap / .deps).
--
-- The version prober is DATA (elixir / iex print the Erlang/OTP line first — the Elixir/IEx/Mix line is
-- preferred). elixir-ls / lexical / next-ls keep their bespoke server-config modules.
--
---@module "lvim-lang.providers.elixir"

local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")
local detect = require("lvim-lang.core.detect")
local core_toolchain = require("lvim-lang.core.toolchain")

---@type LvimLangSpecData
local DATA = {
    name = "elixir",
    filetypes = { "elixir", "eelixir", "heex" },
    root_patterns = { "mix.exs", ".git" },

    runtime = {
        bin = "elixir",
        key = "elixir",
        lookup_key = "elixir_lookup_cmd",
        require = true,
        label = "Elixir runtime",
        hint = "Install Elixir via a version manager (mise / asdf) and pin it with .tool-versions, or set "
            .. "providers.elixir.bin_paths.elixir; the language server, mix tasks and ExUnit all need it.",
    },
    -- elixir / iex print the Erlang/OTP line first — prefer the Elixir/IEx/Mix line, else the first line.
    version = function(bin)
        local out = vim.fn.systemlist({ bin, "--version" })
        if vim.v.shell_error ~= 0 or type(out) ~= "table" then
            return nil
        end
        local first
        for _, line in ipairs(out) do
            local trimmed = vim.trim(line)
            if trimmed ~= "" then
                first = first or trimmed
                if trimmed:match("^Elixir ") or trimmed:match("^IEx ") or trimmed:match("^Mix ") then
                    return trimmed
                end
            end
        end
        return first
    end,

    lsp = {
        servers = {
            ["elixir-ls"] = {
                mason = "elixir-ls",
                bin = "elixir-ls",
                filetypes = { "elixir", "eelixir", "heex" },
                role = "types", -- completion / hover / definition / rename / format / diagnostics
                settings = {
                    elixirLS = {
                        dialyzerEnabled = true,
                        dialyzerFormat = "dialyxir_long",
                        fetchDeps = false,
                        enableTestLenses = false,
                        suggestSpecs = true,
                        mixEnv = "test",
                        autoInsertRequiredAlias = true,
                    },
                },
            },
            lexical = {
                mason = "lexical",
                bin = "lexical",
                filetypes = { "elixir", "eelixir", "heex" },
                role = "types",
                settings = {},
            },
            ["next-ls"] = {
                mason = "next-ls",
                bin = "nextls",
                filetypes = { "elixir", "eelixir", "heex" },
                role = "types",
                settings = {},
            },
        },
        default = "elixir-ls",
    },

    ft = {
        elixir = {
            formatters = {
                mix_format = {
                    efm = {
                        formatCommand = "mix format -",
                        formatStdin = true,
                        rootMarkers = { "mix.exs", ".formatter.exs" },
                    },
                },
            },
            linters = {
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

    icons = {
        statusline = "", -- the Elixir marker in the statusline segment (nf-seti-elixir)
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗", -- hex / mix dependency row
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND ─────────────────────────────────────────────────────────────────────────────────────────

--- A tool `bin` inside the SELECTED elixir's bin dir (where mix / iex live beside `elixir`):
--- `<dirname(elixir)>/<bin>`. Tracks a version-managed elixir's own tools.
---@param bin string
---@return fun(root: string): string|nil
local function in_elixir_bin(bin)
    return function(root)
        local elixir = core_toolchain.resolve("elixir", "elixir", root)
        if not elixir then
            return nil
        end
        local path = vim.fs.joinpath(vim.fs.dirname(elixir), bin)
        return vim.fn.executable(path) == 1 and path or nil
    end
end

local tc = spec.toolchain.tools
-- mix / iex ship with elixir: config → the selected elixir's bin → version manager → PATH.
tc.mix = {
    { kind = "path", value = detect.explicit("elixir", "mix") },
    { kind = "path", value = in_elixir_bin("mix") },
    { kind = "path", value = detect.via_version_manager("elixir", "mix") },
    { kind = "which", value = "mix" },
}
tc.iex = {
    { kind = "path", value = in_elixir_bin("iex") },
    { kind = "path", value = detect.via_version_manager("elixir", "iex") },
    { kind = "which", value = "iex" },
}
-- The elixir-ls debug adapter — a second binary in the elixir-ls mason package (commands resolve it by name).
tc["elixir-ls-debugger"] = detect.mason_strategies("elixir", "elixir-ls-debugger")
-- next-ls' server module resolves by the BINARY name — alias it onto the factory's server-key strategy.
tc.nextls = tc["next-ls"]

-- Debug adapter tuning: the files the elixir-ls debugger compiles before an ExUnit `test` task runs.
defaults.dap = { test_require_files = { "test/**/test_helper.exs", "test/**/*_test.exs" } }

spec.commands = require("lvim-lang.providers.elixir.commands")
spec.tasks = require("lvim-lang.providers.elixir.deps").templates

registry.register(spec, defaults)

return spec
