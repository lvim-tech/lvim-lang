-- lvim-lang.providers.zig.commands: the Zig subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. The command surface adapts to the project shape at run time
-- (build.zig project vs single file) — see providers.zig.tasks.
--
---@module "lvim-lang.providers.zig.commands"

local tasks = require("lvim-lang.providers.zig.tasks")
local deps = require("lvim-lang.providers.zig.deps")
local test = require("lvim-lang.providers.zig.test")
local dap = require("lvim-lang.providers.zig.dap")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    build = { impl = tasks.build, desc = "zig build (or zig build-exe <file> for a single file)" },
    run = { impl = tasks.run, desc = "zig build run / zig run <file> (+ active run config)" },
    test = { impl = tasks.test, desc = "zig build test / zig test <file>" },
    ["test-func"] = { impl = test.func, desc = "run the `test` block under the cursor (--test-filter)" },
    fmt = { impl = tasks.fmt, desc = "zig fmt [path] — the formatter built into the zig binary" },
    fetch = { impl = deps.fetch, desc = "zig fetch --save <url|path> — add a dependency to build.zig.zon" },
    deps = {
        impl = deps.command,
        desc = "deps <fetch> — prefetch declared dependencies",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, deps.subs())
        end,
    },
    debug = { impl = dap.debug, desc = "start / continue an lldb-dap / codelldb debug session (lvim-dap)" },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
