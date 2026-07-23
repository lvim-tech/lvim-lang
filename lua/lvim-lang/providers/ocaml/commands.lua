-- lvim-lang.providers.ocaml.commands: the OCaml subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. The whole surface is dune-driven (build / exec / test / utop /
-- fmt), plus opam dependency operations, earlybird debugging and run configs.
--
---@module "lvim-lang.providers.ocaml.commands"

local tasks = require("lvim-lang.providers.ocaml.tasks")
local test = require("lvim-lang.providers.ocaml.test")
local deps = require("lvim-lang.providers.ocaml.deps")
local dap = require("lvim-lang.providers.ocaml.dap")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    build = { impl = tasks.build, desc = "dune build [args]" },
    run = { impl = tasks.run, desc = "dune exec <target> (+ active run config)" },
    exec = { impl = tasks.exec, desc = "dune exec <target> [-- args] (raw, no run config)" },
    test = { impl = tasks.test, desc = "dune test [args]" },
    ["test-func"] = {
        impl = test.func,
        desc = "run the test directory of the file under the cursor (dune runtest <dir>)",
    },
    fmt = { impl = tasks.fmt, desc = "dune build @fmt --auto-promote (ocamlformat)" },
    utop = { impl = tasks.utop, desc = "dune utop [dir] — a REPL with the project's libraries" },
    deps = {
        impl = deps.command,
        desc = "deps <install|list|upgrade> — opam dependency operations",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, deps.subs())
        end,
    },
    debug = { impl = dap.debug, desc = "start / continue an earlybird debug session (lvim-dap)" },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
