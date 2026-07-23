-- lvim-lang.providers.swift.commands: the Swift subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. The one-shot `swift` CLI tasks (build / run / test / clean /
-- fmt), the SwiftPM dependency commands, the test-under-cursor runner, and lldb debugging.
--
---@module "lvim-lang.providers.swift.commands"

local tasks = require("lvim-lang.providers.swift.tasks")
local deps = require("lvim-lang.providers.swift.deps")
local test = require("lvim-lang.providers.swift.test")
local dap = require("lvim-lang.providers.swift.dap")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    build = { impl = tasks.build, desc = "swift build [args]" },
    run = { impl = tasks.run, desc = "swift run [args] (+ active run config)" },
    test = { impl = tasks.test, desc = "swift test [args]" },
    ["test-func"] = { impl = test.func, desc = "run the XCTest method under the cursor" },
    clean = { impl = tasks.clean, desc = "swift package clean [args]" },
    fmt = { impl = tasks.fmt, desc = "swiftformat [args] — format the package" },
    update = { impl = deps.update, desc = "swift package update" },
    deps = {
        impl = deps.command,
        desc = "deps <resolve|update|describe|show-dependencies> — SwiftPM dependency commands",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, deps.subs())
        end,
    },
    debug = { impl = dap.debug, desc = "start / continue an lldb-dap debug session (lvim-dap)" },
    ["debug-test"] = { impl = dap.debug_test, desc = "debug the XCTest method under the cursor (lldb-dap)" },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
