-- lvim-lang.providers.java.commands: the Java subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. build / run / test go through the detected build tool (Gradle
-- or Maven); test-func / test-file target a single JUnit method / class; deps inspects the
-- dependency graph; debug / debug-test drive java-debug; config picks the active run configuration.
--
---@module "lvim-lang.providers.java.commands"

local tasks = require("lvim-lang.providers.java.tasks")
local test = require("lvim-lang.providers.java.test")
local deps = require("lvim-lang.providers.java.deps")
local dap = require("lvim-lang.providers.java.dap")
local refactor = require("lvim-lang.providers.java.refactor")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    build = { impl = tasks.build, desc = "gradle build / mvn compile [args]" },
    run = { impl = tasks.run, desc = "gradle run / mvn exec:java [args] (applies the active run config)" },
    test = { impl = tasks.test, desc = "gradle test / mvn test — the whole suite [args]" },
    ["test-func"] = { impl = test.func, desc = "run the JUnit method under the cursor" },
    ["test-file"] = { impl = test.file, desc = "run every JUnit test in the current class" },
    deps = {
        impl = deps.command,
        desc = "deps tree|refresh|install — dependency graph / re-resolve / install",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, deps.subs())
        end,
    },
    debug = { impl = dap.debug, desc = "debug a discovered main class (jdtls resolveMainClass; picker if several)" },
    ["debug-test"] = { impl = dap.debug_test, desc = "debug the JUnit method under the cursor (remote-debug + attach)" },
    ["organize-imports"] = { impl = refactor.organize_imports, desc = "jdtls: remove unused + order imports" },
    ["extract-variable"] = {
        impl = refactor.extract_variable,
        desc = "jdtls: extract the visual selection into a local",
    },
    ["extract-constant"] = {
        impl = refactor.extract_constant,
        desc = "jdtls: extract the visual selection into a constant",
    },
    ["extract-method"] = { impl = refactor.extract_method, desc = "jdtls: extract the visual selection into a method" },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
