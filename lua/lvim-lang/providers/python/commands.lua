-- lvim-lang.providers.python.commands: the Python subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. Covers running (`run` / `run-module` / `check`), testing
-- (`test` / `test-file` / `test-func` / `unittest` / `coverage`), the interpreter / venv picker,
-- dependency management, type-stub codegen, DAP and the run-config picker.
--
---@module "lvim-lang.providers.python.commands"

local tasks = require("lvim-lang.providers.python.tasks")
local test = require("lvim-lang.providers.python.test")
local deps = require("lvim-lang.providers.python.deps")
local codegen = require("lvim-lang.providers.python.codegen")
local dap = require("lvim-lang.providers.python.dap")
local venv = require("lvim-lang.providers.python.venv")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    run = { impl = tasks.run, desc = "run the current file (+ active run config) under the venv interpreter" },
    ["run-module"] = { impl = tasks.run_module, desc = "python -m <module> [args]" },
    check = { impl = tasks.check, desc = "python -m compileall — byte-compile sanity pass" },
    test = { impl = test.suite, desc = "pytest [args] — the whole suite" },
    ["test-file"] = { impl = test.file, desc = "pytest — the current file" },
    ["test-func"] = { impl = test.func, desc = "run the `def test_*` under the cursor (pytest node id)" },
    unittest = { impl = test.unittest, desc = "python -m unittest [target] (discover by default)" },
    coverage = {
        impl = test.coverage,
        desc = "coverage [clear] — coverage run -m pytest + gutter overlay",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, { "clear" })
        end,
    },
    venv = {
        impl = venv.command,
        desc = "venv [create [name]] — pick / create the interpreter (virtual environment)",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, { "create" })
        end,
    },
    add = { impl = deps.add, desc = "add <package…> — add a dependency (auto-detected manager)" },
    remove = { impl = deps.remove, desc = "remove <package…> — remove a dependency" },
    update = { impl = deps.update, desc = "update [package…] — update dependencies" },
    deps = {
        impl = deps.command,
        desc = "deps <install|update|tree|lock> — dependency commands",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, deps.subs())
        end,
    },
    stub = { impl = codegen.stub, desc = "stub <import> — generate .pyi type stubs (basedpyright)" },
    debug = { impl = dap.debug, desc = "start / continue a debugpy debug session (lvim-dap)" },
    ["debug-test"] = { impl = dap.debug_test, desc = "debug the pytest test under the cursor" },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
