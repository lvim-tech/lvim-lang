-- lvim-lang.providers.erlang.commands: the Erlang subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. compile / shell drive the rebar3 build + REPL; eunit / ct run
-- the whole test suites; test-func / test-file run the EUnit test under the cursor / current module;
-- ct-suite runs the current Common Test suite; fmt runs erlfmt; deps manages rebar3 dependencies;
-- config picks the active run configuration. Erlang has NO reliable mason debug adapter, so no debug
-- commands are exposed (see docs/providers/erlang.md).
--
---@module "lvim-lang.providers.erlang.commands"

local tasks = require("lvim-lang.providers.erlang.tasks")
local test = require("lvim-lang.providers.erlang.test")
local deps = require("lvim-lang.providers.erlang.deps")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    compile = { impl = tasks.compile, desc = "rebar3 compile [args]" },
    shell = { impl = tasks.shell, desc = "rebar3 shell [args] (+ active run config)" },
    eunit = { impl = tasks.eunit, desc = "rebar3 eunit [args] — the whole project" },
    ct = { impl = tasks.ct, desc = "rebar3 ct [args] — the whole project" },
    ["test-func"] = { impl = test.func, desc = "run the EUnit test function under the cursor" },
    ["test-file"] = { impl = test.file, desc = "run every EUnit test in the current module" },
    ["ct-suite"] = { impl = test.ct_suite, desc = "run the current Common Test suite (*_SUITE.erl)" },
    fmt = { impl = tasks.fmt, desc = "erlfmt --write <current file>" },
    deps = {
        impl = deps.command,
        desc = "deps <get|upgrade|tree> — rebar3 dependency commands",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, deps.subs())
        end,
    },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
