-- lvim-lang.providers.elixir.commands: the Elixir subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. compile / run / iex drive mix + iex; format / credo format +
-- lint; test / test-file / test-func drive ExUnit (whole suite / current file / test under the
-- cursor); deps manages Hex dependencies; debug / debug-test drive the elixir-ls debugger; config
-- picks the active run configuration.
--
---@module "lvim-lang.providers.elixir.commands"

local tasks = require("lvim-lang.providers.elixir.tasks")
local test = require("lvim-lang.providers.elixir.test")
local deps = require("lvim-lang.providers.elixir.deps")
local dap = require("lvim-lang.providers.elixir.dap")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    compile = { impl = tasks.compile, desc = "mix compile [args]" },
    run = { impl = tasks.run, desc = "mix run [args] (applies the active run config)" },
    iex = { impl = tasks.iex, desc = "iex -S mix [args] — interactive shell in the project" },
    format = { impl = tasks.format, desc = "mix format [args]" },
    credo = { impl = tasks.credo, desc = "mix credo [args] — static analysis / linting" },
    test = { impl = test.suite, desc = "mix test — the whole suite [args]" },
    ["test-file"] = { impl = test.file, desc = "run every ExUnit test in the current file" },
    ["test-func"] = { impl = test.func, desc = "run the ExUnit test under the cursor (mix test file:line)" },
    deps = {
        impl = deps.command,
        desc = "deps <get|update|tree|clean|unlock> — Hex dependency commands",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, deps.subs())
        end,
    },
    debug = { impl = dap.debug, desc = "start / continue an elixir-ls debug session (lvim-dap)" },
    ["debug-test"] = { impl = dap.debug_test, desc = "debug the ExUnit test under the cursor (elixir-ls)" },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
