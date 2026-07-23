-- lvim-lang.providers.haskell.commands: the Haskell subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. build / run / test / clean go through the detected build tool
-- (Stack or Cabal); test-func / test-file target the hspec example / file suites; deps inspects /
-- resolves dependencies; debug drives haskell-debug-adapter; config picks the active run configuration.
--
---@module "lvim-lang.providers.haskell.commands"

local tasks = require("lvim-lang.providers.haskell.tasks")
local test = require("lvim-lang.providers.haskell.test")
local deps = require("lvim-lang.providers.haskell.deps")
local dap = require("lvim-lang.providers.haskell.dap")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    build = { impl = tasks.build, desc = "stack build / cabal build [args]" },
    run = { impl = tasks.run, desc = "stack run / cabal run [args] (applies the active run config)" },
    test = { impl = tasks.test, desc = "stack test / cabal test — the whole suite [args]" },
    ["test-func"] = { impl = test.func, desc = "run the hspec describe/it example under the cursor" },
    ["test-file"] = { impl = test.file, desc = "run the current file's top-level hspec suites" },
    clean = { impl = tasks.clean, desc = "stack clean / cabal clean [args]" },
    deps = {
        impl = deps.command,
        desc = "deps resolve|freeze|list|outdated — dependency resolution / inspection",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, deps.subs())
        end,
    },
    debug = { impl = dap.debug, desc = "start / continue a haskell-debug-adapter session (lvim-dap)" },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
