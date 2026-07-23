-- lvim-lang.providers.kotlin.commands: the Kotlin subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. build / run / test go through the detected build tool (Gradle
-- or Maven); test-func / test-file target a single test function / class; deps inspects the
-- dependency graph; debug / debug-test drive kotlin-debug-adapter; config picks the active run
-- configuration.
--
---@module "lvim-lang.providers.kotlin.commands"

local tasks = require("lvim-lang.providers.kotlin.tasks")
local test = require("lvim-lang.providers.kotlin.test")
local deps = require("lvim-lang.providers.kotlin.deps")
local dap = require("lvim-lang.providers.kotlin.dap")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    build = { impl = tasks.build, desc = "gradle build / mvn compile [args]" },
    run = { impl = tasks.run, desc = "gradle run / mvn exec:java [args] (applies the active run config)" },
    test = { impl = tasks.test, desc = "gradle test / mvn test — the whole suite [args]" },
    ["test-func"] = { impl = test.func, desc = "run the test function under the cursor" },
    ["test-file"] = { impl = test.file, desc = "run every test in the current class" },
    deps = {
        impl = deps.command,
        desc = "deps tree|refresh|install — dependency graph / re-resolve / install",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, deps.subs())
        end,
    },
    debug = { impl = dap.debug, desc = "start / continue a kotlin-debug-adapter session (lvim-dap)" },
    ["debug-test"] = {
        impl = dap.debug_test,
        desc = "debug the test function under the cursor (remote-debug + attach)",
    },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
