-- lvim-lang.providers.typescript.commands: the TypeScript/JS subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. Covers running (`run` / `script` / `install` / `build` / `dev`),
-- testing (`test` / `test-file` / `test-func` / `coverage`), dependency management, `.d.ts` codegen,
-- DAP and the run-config picker. The `script` command completes against the buffer's package.json.
--
---@module "lvim-lang.providers.typescript.commands"

local tasks = require("lvim-lang.providers.typescript.tasks")
local test = require("lvim-lang.providers.typescript.test")
local deps = require("lvim-lang.providers.typescript.deps")
local codegen = require("lvim-lang.providers.typescript.codegen")
local dap = require("lvim-lang.providers.typescript.dap")
local pm = require("lvim-lang.providers.typescript.pm")
local runcfg = require("lvim-lang.core.runcfg")

--- Prefix-filter a candidate list against the current completion argument.
---@param arg string
---@param candidates string[]
---@return string[]
local function filter(arg, candidates)
    return vim.tbl_filter(function(s)
        return arg == "" or s:find(arg, 1, true) == 1
    end, candidates)
end

--- Complete the `script` subcommand with the buffer's package.json script names.
---@param arg string
---@return string[]
local function complete_scripts(arg)
    local _, root = require("lvim-lang.registry").for_buffer()
    if not root then
        return {}
    end
    local names = {}
    for _, s in ipairs(pm.scripts(root)) do
        names[#names + 1] = s.name
    end
    return filter(arg, names)
end

---@type table<string, LvimLangCommand>
local M = {
    run = { impl = tasks.run, desc = "run the current file (node/tsx) or the active run config" },
    script = {
        impl = tasks.script,
        desc = "script [name] — run a package.json script (picker if none)",
        complete = complete_scripts,
    },
    install = { impl = tasks.install, desc = "install dependencies (auto-detected package manager)" },
    build = { impl = tasks.build, desc = "run the `build` script" },
    dev = { impl = tasks.dev, desc = "run the `dev` script" },
    test = { impl = test.suite, desc = "run the whole suite (vitest / jest)" },
    ["test-file"] = { impl = test.file, desc = "run the current file's tests" },
    ["test-func"] = { impl = test.func, desc = "run the it()/test() under the cursor (-t <title>)" },
    coverage = {
        impl = test.coverage,
        desc = "coverage [clear] — run with a JSON reporter + gutter overlay",
        complete = function(arg)
            return filter(arg, { "clear" })
        end,
    },
    add = { impl = deps.add, desc = "add <package…> — add a dependency" },
    remove = { impl = deps.remove, desc = "remove <package…> — remove a dependency" },
    update = { impl = deps.update, desc = "update [package…] — update dependencies" },
    deps = {
        impl = deps.command,
        desc = "deps <install|update|outdated> — dependency commands",
        complete = function(arg)
            return filter(arg, deps.subs())
        end,
    },
    types = { impl = codegen.types, desc = "emit .d.ts declarations (tsc --declaration)" },
    debug = { impl = dap.debug, desc = "start / continue a js-debug session (lvim-dap)" },
    ["debug-test"] = { impl = dap.debug_test, desc = "debug the test under the cursor" },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
