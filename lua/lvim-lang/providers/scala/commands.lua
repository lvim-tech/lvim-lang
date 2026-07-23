-- lvim-lang.providers.scala.commands: the Scala subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. build / run / test go through the detected build tool (sbt /
-- mill / bloop); test-func / test-file target the enclosing suite / file's suite; deps inspects the
-- dependency graph; debug / debug-test drive metals' own debug adapter; config picks the active run
-- configuration.
--
---@module "lvim-lang.providers.scala.commands"

local tasks = require("lvim-lang.providers.scala.tasks")
local test = require("lvim-lang.providers.scala.test")
local deps = require("lvim-lang.providers.scala.deps")
local dap = require("lvim-lang.providers.scala.dap")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    build = { impl = tasks.build, desc = "sbt compile / mill __.compile / bloop compile [args]" },
    run = { impl = tasks.run, desc = "sbt run / mill <module>.run / bloop run (applies the active run config)" },
    test = { impl = tasks.test, desc = "sbt test / mill __.test / bloop test — the whole suite [args]" },
    ["test-func"] = { impl = test.func, desc = "run the enclosing test suite (Scala isolates per-suite)" },
    ["test-file"] = { impl = test.file, desc = "run every test in the current buffer's suite" },
    deps = {
        impl = deps.command,
        desc = "deps tree|refresh|install — dependency graph / re-resolve / publishLocal",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, deps.subs())
        end,
    },
    debug = { impl = dap.debug, desc = "start / continue a metals debug session (lvim-dap)" },
    ["debug-test"] = { impl = dap.debug_test, desc = "debug the current buffer's test suite(s) via metals" },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
