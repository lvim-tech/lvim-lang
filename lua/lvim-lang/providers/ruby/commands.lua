-- lvim-lang.providers.ruby.commands: the Ruby subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. run runs the current file; test / test-file / test-func drive
-- RSpec (whole suite / current file / example under the cursor); rake runs a rake task; rubocop /
-- rubocop-fix lint / autocorrect; deps + add / remove / update manage bundler gems; debug /
-- debug-test drive rdbg; config picks the active run configuration.
--
---@module "lvim-lang.providers.ruby.commands"

local tasks = require("lvim-lang.providers.ruby.tasks")
local test = require("lvim-lang.providers.ruby.test")
local deps = require("lvim-lang.providers.ruby.deps")
local dap = require("lvim-lang.providers.ruby.dap")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    run = { impl = tasks.run, desc = "ruby <current file> [args] (applies the active run config)" },
    test = { impl = test.suite, desc = "rspec — the whole suite [args]" },
    ["test-file"] = { impl = test.file, desc = "run every RSpec example in the current file" },
    ["test-func"] = { impl = test.func, desc = "run the RSpec example under the cursor (rspec file:line)" },
    rake = { impl = tasks.rake, desc = "rake [task] [args] (bundle exec when bundled)" },
    rubocop = { impl = tasks.rubocop, desc = "rubocop [args] — lint the project" },
    ["rubocop-fix"] = { impl = tasks.rubocop_fix, desc = "rubocop -A [args] — autocorrect" },
    add = { impl = deps.add, desc = "bundle add <gem> [--version …]" },
    remove = { impl = deps.remove, desc = "bundle remove <gem…>" },
    update = { impl = deps.update, desc = "bundle update [gem…]" },
    deps = {
        impl = deps.command,
        desc = "deps <install|update|outdated> — bundler dependency commands",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, deps.subs())
        end,
    },
    debug = { impl = dap.debug, desc = "start / continue an rdbg debug session (lvim-dap)" },
    ["debug-test"] = { impl = dap.debug_test, desc = "debug the RSpec example under the cursor (rdbg)" },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
