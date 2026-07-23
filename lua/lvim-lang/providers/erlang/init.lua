-- lvim-lang.providers.erlang: the Erlang provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes/root, the erlang-ls catalog, the per-filetype tool catalog (erlfmt formatter), the erl
-- + rebar3 toolchain, the erl + rebar3 requirements, health and statusline. This module then EXTENDS the
-- returned spec with Erlang's idiosyncratic parts:
--   * rebar3 resolution (the project-vendored `<root>/rebar3` escript, before PATH);
--   * a bin-keyed alias (erlang-ls' server module resolves by the BINARY `erlang_ls`, not the catalog key);
--   * the rebar3 build/test + dependency command surface (providers.erlang.commands / .deps).
--
-- The version prober is DATA (erl has no `--version` flag — its OTP release is read out of the emulator).
-- erlang-ls keeps its bespoke servers/erlang-ls.lua (a real file wins over the generic shim).
--
---@module "lvim-lang.providers.erlang"

local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")

---@type LvimLangSpecData
local DATA = {
    name = "erlang",
    filetypes = { "erlang" },
    root_patterns = { "rebar.config", "erlang.mk", ".git" },

    runtimes = {
        {
            bin = "erl",
            key = "erl",
            lookup_key = "erl_lookup_cmd",
            require = true,
            label = "Erlang/OTP runtime",
            hint = "Install Erlang/OTP via a version manager (mise / asdf / kerl) and put `erl` on PATH, or "
                .. "set providers.erlang.bin_paths.erl; the language server needs it.",
        },
        {
            bin = "rebar3",
            key = "rebar3",
            require = true,
            label = "rebar3 build tool",
            hint = "Install rebar3 (the Erlang build tool) and put it on PATH, vendor it at the project root, "
                .. "or set providers.erlang.bin_paths.rebar3; build / test commands need it.",
        },
    },
    -- erl has no `--version` flag — read the OTP release out of the emulator; the mason tools use --version.
    version = function(bin)
        local out
        if vim.fs.basename(bin) == "erl" then
            out = vim.fn.systemlist({
                bin,
                "-noshell",
                "-eval",
                'io:format("OTP ~s~n", [erlang:system_info(otp_release)]), halt().',
            })
        else
            out = vim.fn.systemlist({ bin, "--version" })
        end
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
    end,

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

    ft = {
        erlang = {
            formatters = {
                erlfmt = { mason = "erlfmt", efm = { formatCommand = "erlfmt -", formatStdin = true } },
            },
            linters = {},
            debuggers = {},
            -- erlang_ls does not format Erlang → erlfmt is the default formatter; it provides diagnostics
            -- so no default linter; Erlang has no reliable mason debug adapter, so no debugger.
            defaults = { formatter = "erlfmt", linter = false, debugger = false },
        },
    },

    icons = {
        statusline = "", -- the Erlang marker in the statusline segment (nf-dev-erlang, U+E7B1)
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        deps = "󰏗",
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND ─────────────────────────────────────────────────────────────────────────────────────────

local tc = spec.toolchain.tools
-- rebar3: an explicit path → the project-vendored escript (`<root>/rebar3`, how many projects pin it) → PATH.
tc.rebar3 = {
    { kind = "path", value = require("lvim-lang.core.detect").explicit("erlang", "rebar3") },
    {
        kind = "path",
        value = function(root)
            local path = vim.fs.joinpath(root, "rebar3")
            return vim.fn.executable(path) == 1 and path or nil
        end,
    },
    { kind = "which", value = "rebar3" },
}
-- erlang-ls' server module resolves by the BINARY name — alias it onto the factory's server-key strategy.
tc.erlang_ls = tc["erlang-ls"]

spec.commands = require("lvim-lang.providers.erlang.commands")
spec.tasks = require("lvim-lang.providers.erlang.deps").templates

registry.register(spec, defaults)

return spec
