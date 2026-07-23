-- lvim-lang.providers.fsharp.commands: the F# subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. Wires the one-shot `dotnet` CLI tasks (build / run / test /
-- clean), Fantomas formatting, tests (whole file / under the cursor), NuGet dependency commands, and
-- netcoredbg debugging.
--
---@module "lvim-lang.providers.fsharp.commands"

local tasks = require("lvim-lang.providers.fsharp.tasks")
local test = require("lvim-lang.providers.fsharp.test")
local deps = require("lvim-lang.providers.fsharp.deps")
local dap = require("lvim-lang.providers.fsharp.dap")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    build = { impl = tasks.build, desc = "dotnet build [args]" },
    run = { impl = tasks.run, desc = "dotnet run [args] (+ active run config)" },
    test = { impl = tasks.test, desc = "dotnet test [args]" },
    ["test-func"] = { impl = test.func, desc = "run the [<Fact>]/[<Theory>]/[<Test>]/… binding under the cursor" },
    ["test-file"] = { impl = test.file, desc = "dotnet test — every attributed test in the current buffer" },
    clean = { impl = tasks.clean, desc = "dotnet clean [args]" },
    format = { impl = tasks.format, desc = "fantomas [paths…] — format the current file / paths" },
    add = { impl = deps.add, desc = "dotnet add package <package[@version]> [args]" },
    remove = { impl = deps.remove, desc = "dotnet remove package <package>" },
    restore = { impl = deps.restore, desc = "dotnet restore [args]" },
    deps = {
        impl = deps.command,
        desc = "deps <restore|list> — NuGet dependency commands",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, deps.subs())
        end,
    },
    debug = { impl = dap.debug, desc = "start / continue a netcoredbg debug session (lvim-dap)" },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
