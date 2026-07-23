-- lvim-lang.providers.csharp.commands: the C# subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. Wires the one-shot `dotnet` CLI tasks (build / run / test /
-- clean), tests (whole file / under the cursor), NuGet dependency commands, and netcoredbg debugging.
--
---@module "lvim-lang.providers.csharp.commands"

local tasks = require("lvim-lang.providers.csharp.tasks")
local test = require("lvim-lang.providers.csharp.test")
local deps = require("lvim-lang.providers.csharp.deps")
local dap = require("lvim-lang.providers.csharp.dap")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    build = { impl = tasks.build, desc = "dotnet build [args]" },
    run = { impl = tasks.run, desc = "dotnet run [args] (+ active run config)" },
    test = { impl = tasks.test, desc = "dotnet test [args]" },
    ["test-func"] = { impl = test.func, desc = "run the [Fact]/[Theory]/[Test]/[TestMethod] under the cursor" },
    ["test-file"] = { impl = test.file, desc = "dotnet test — the current buffer's test class" },
    clean = { impl = tasks.clean, desc = "dotnet clean [args]" },
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
