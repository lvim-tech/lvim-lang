-- lvim-lang.providers.go.commands: the Go subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. Grows per milestone — G3 wires the one-shot `go` CLI tasks
-- (build / run / test / vet / generate); modules, tests-under-cursor, codegen and DAP follow.
--
---@module "lvim-lang.providers.go.commands"

local tasks = require("lvim-lang.providers.go.tasks")
local mod = require("lvim-lang.providers.go.mod")
local test = require("lvim-lang.providers.go.test")
local codegen = require("lvim-lang.providers.go.codegen")
local dap = require("lvim-lang.providers.go.dap")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    build = { impl = tasks.build, desc = "go build ./... [args]" },
    run = { impl = tasks.run, desc = "go run . [target] [args]" },
    test = { impl = tasks.test, desc = "go test ./... [args]" },
    ["test-func"] = { impl = test.func, desc = "run the Test/Benchmark/Fuzz/Example under the cursor" },
    ["test-file"] = { impl = test.file, desc = "go test — the current buffer's package" },
    coverage = {
        impl = test.coverage,
        desc = "coverage [clear] — go test -coverprofile + gutter overlay",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, { "clear" })
        end,
    },
    vet = { impl = tasks.vet, desc = "go vet ./... [args]" },
    generate = { impl = tasks.generate, desc = "go generate ./... [args]" },
    mod = {
        impl = mod.command,
        desc = "mod tidy|download|verify|graph|why — go module commands",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, mod.subs())
        end,
    },
    get = { impl = mod.get, desc = "go get <module[@version]> | -u ./... — add / upgrade a dependency" },
    tags = {
        impl = codegen.tags,
        desc = "tags <add|remove> [json|xml|…] — struct tags at the cursor (gomodifytags)",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, { "add", "remove" })
        end,
    },
    gotests = { impl = codegen.gotests, desc = "generate a table-driven test for the function at the cursor" },
    impl = { impl = codegen.impl, desc = "impl <receiver…> <interface> — generate interface method stubs" },
    debug = { impl = dap.debug, desc = "start / continue a Delve debug session (lvim-dap)" },
    ["debug-test"] = { impl = dap.debug_test, desc = "debug the test under the cursor (Delve, -test.run)" },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
