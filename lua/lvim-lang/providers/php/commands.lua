-- lvim-lang.providers.php.commands: the PHP subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. run executes a script; test / test-func / test-file drive
-- PHPUnit; analyse runs project-wide phpstan; cs-fix runs php-cs-fixer; serve starts the built-in web
-- server; require / remove / deps are Composer dependency commands; debug drives php-debug-adapter
-- (Xdebug); config picks the active run configuration.
--
---@module "lvim-lang.providers.php.commands"

local tasks = require("lvim-lang.providers.php.tasks")
local test = require("lvim-lang.providers.php.test")
local deps = require("lvim-lang.providers.php.deps")
local dap = require("lvim-lang.providers.php.dap")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    run = { impl = tasks.run, desc = "php <script> [args] (+ active run config; defaults to the current file)" },
    test = { impl = tasks.test, desc = "phpunit — the whole suite [args]" },
    ["test-func"] = { impl = test.func, desc = "run the PHPUnit method under the cursor" },
    ["test-file"] = { impl = test.file, desc = "run every PHPUnit test in the current file" },
    analyse = { impl = tasks.analyse, desc = "phpstan analyse — project-wide static analysis [args]" },
    ["cs-fix"] = { impl = tasks.cs_fix, desc = "php-cs-fixer fix — project-wide code-style fixing [args]" },
    serve = { impl = tasks.serve, desc = "php -S host:port — the built-in development web server [args]" },
    require = { impl = deps.require, desc = "composer require <package[:constraint]> [args]" },
    remove = { impl = deps.remove, desc = "composer remove <package>" },
    deps = {
        impl = deps.command,
        desc = "deps <install|update|dump-autoload> — Composer dependency commands",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, deps.subs())
        end,
    },
    debug = { impl = dap.debug, desc = "start / continue a php-debug-adapter (Xdebug) session (lvim-dap)" },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
