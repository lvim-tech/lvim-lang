-- lvim-lang.providers.php.tasks: one-shot PHP commands run through lvim-tasks.
-- PHP has no compile step, so the verbs are: `run` (execute a script with the CLI runtime), `test`
-- (the whole PHPUnit suite), `analyse` (project-wide phpstan), `cs-fix` (project-wide php-cs-fixer)
-- and `serve` (the built-in development web server). They are fire-and-collect commands, so they go
-- through core.runner → lvim-tasks (its panel / history / dock). PHP's CLI emits
-- `PHP … error: message in <file> on line <N>`, routed to the quickfix by the built-in `generic`
-- matcher. Extra command-line args are appended (e.g. `:LvimLang run script.php arg`).
--
---@module "lvim-lang.providers.php.tasks"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The PHP provider's config block.
---@return table
local function opts()
    return config.providers.php or {}
end

--- Resolve the PHP project root for the current buffer (nearest `composer.json`, else `.git`, else
--- the file's directory, else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "composer.json", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run a resolved tool `argv` for a root through lvim-tasks (`generic` matcher). `env` (optional) is
--- passed to the task process.
---@param provider_tool string  toolchain tool key to resolve (e.g. "php", "phpstan")
---@param fallback string       bare binary name if the tool cannot be resolved
---@param root string
---@param argv string[]
---@param name string
---@param group string
---@param env? table<string, string>
---@return nil
local function run_tool(provider_tool, fallback, root, argv, name, group, env)
    local bin = toolchain.resolve("php", provider_tool, root) or fallback
    local cmd = { bin }
    vim.list_extend(cmd, argv)
    runner.run("php", { name = name, cmd = cmd, cwd = root, group = group, matcher = "generic", env = env })
end

--- `:LvimLang run [script] [args]` — execute a script with the PHP CLI runtime. When a run config is
--- active (`.lvim/lang/run.lua`) it supplies the script, program args and env; an explicit first CLI
--- token overrides the script, the rest are program args. With neither, the current buffer's file runs.
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    local root = ctx.root or resolve_root()
    local rc = require("lvim-lang.core.runcfg").active(root)
    local script, prog, env = nil, {}, nil
    if rc then
        script = rc.script
        vim.list_extend(prog, rc.args or {})
        env = rc.env
    end
    if args[1] then
        -- A first CLI token names the script; remaining tokens are program args.
        script = args[1]
        prog = { unpack(args, 2) }
    elseif rc then
        vim.list_extend(prog, args)
    else
        vim.list_extend(prog, args)
    end
    script = script or vim.api.nvim_buf_get_name(ctx.bufnr or vim.api.nvim_get_current_buf())
    if not script or script == "" then
        vim.notify("lvim-lang: no script to run (open a .php file or pass one)", vim.log.levels.WARN, TITLE)
        return
    end
    local argv = { script }
    vim.list_extend(argv, prog)
    run_tool("php", "php", root, argv, "php " .. vim.fs.basename(script), "Run", env)
end

--- `:LvimLang test [args]` — the whole PHPUnit suite (test-func / test-file are in test.lua).
---@param args string[]
---@param ctx table
---@return nil
function M.test(args, ctx)
    local root = ctx.root or resolve_root()
    local argv = {}
    vim.list_extend(argv, args)
    run_tool("phpunit", "phpunit", root, argv, "phpunit", "Test")
end

--- `:LvimLang analyse [args]` — project-wide static analysis with phpstan (reads the project's
--- `phpstan.neon` for its level / paths).
---@param args string[]
---@param ctx table
---@return nil
function M.analyse(args, ctx)
    local root = ctx.root or resolve_root()
    local argv = { "analyse", "--no-progress" }
    vim.list_extend(argv, args)
    run_tool("phpstan", "phpstan", root, argv, "phpstan analyse", "Lint")
end

--- `:LvimLang cs-fix [args]` — project-wide code-style fixing with php-cs-fixer.
---@param args string[]
---@param ctx table
---@return nil
function M.cs_fix(args, ctx)
    local root = ctx.root or resolve_root()
    local argv = { "fix" }
    vim.list_extend(argv, args)
    run_tool("php-cs-fixer", "php-cs-fixer", root, argv, "php-cs-fixer fix", "Build")
end

--- `:LvimLang serve [args]` — the PHP built-in development web server (`php -S host:port` in the
--- configured document root). host / port / docroot come from the provider config (all overridable);
--- extra CLI args append.
---@param args string[]
---@param ctx table
---@return nil
function M.serve(args, ctx)
    local root = ctx.root or resolve_root()
    local o = opts()
    local host = o.serve_host or "localhost"
    local port = o.serve_port or 8000
    local argv = { "-S", ("%s:%s"):format(host, port) }
    if o.serve_docroot and o.serve_docroot ~= "" then
        argv[#argv + 1] = "-t"
        argv[#argv + 1] = o.serve_docroot
    end
    vim.list_extend(argv, args)
    run_tool("php", "php", root, argv, ("php -S %s:%s"):format(host, port), "Run")
end

--- The buffer's project root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
