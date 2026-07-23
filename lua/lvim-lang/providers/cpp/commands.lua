-- lvim-lang.providers.cpp.commands: the C / C++ subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. The command surface adapts to the project's build system at run
-- time (CMake / Make / single file) — see providers.cpp.tasks.
--
---@module "lvim-lang.providers.cpp.commands"

local tasks = require("lvim-lang.providers.cpp.tasks")
local test = require("lvim-lang.providers.cpp.test")
local codegen = require("lvim-lang.providers.cpp.codegen")
local dap = require("lvim-lang.providers.cpp.dap")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    build = { impl = tasks.build, desc = "build the project (cmake build / make / compile the file)" },
    run = { impl = tasks.run, desc = "run the built binary (+ active run config)" },
    test = { impl = tasks.test, desc = "run tests (ctest / make test)" },
    ["test-func"] = { impl = test.func, desc = "run the GoogleTest / Catch2 test under the cursor (ctest -R)" },
    configure = { impl = tasks.configure, desc = "cmake configure into build/ (exports compile_commands.json)" },
    ["compile-commands"] = { impl = codegen.compile_commands, desc = "generate compile_commands.json (cmake / bear)" },
    debug = { impl = dap.debug, desc = "start / continue a CodeLLDB / cpptools debug session (lvim-dap)" },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
