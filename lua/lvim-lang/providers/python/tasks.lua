-- lvim-lang.providers.python.tasks: running Python through lvim-tasks.
-- `run` executes the current file (or the active run config's script / module, with its args / env)
-- under the project's VENV interpreter; `run-module` runs `python -m <module>`. Fire-and-collect,
-- so they go through core.runner → lvim-tasks with the built-in `python` traceback matcher routing
-- `File "…", line N` frames to the quickfix list. Python has no meaningful "build" step — none is
-- invented; use `check` for a byte-compile sanity pass over the tree.
--
---@module "lvim-lang.providers.python.tasks"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

local M = {}

--- Resolve the Python project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", "Pipfile", ".git" })
            or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The venv interpreter for a root (else `python3` / `python`).
---@param root string
---@return string
local function python_bin(root)
    return toolchain.resolve("python", "python", root) or "python3"
end

--- Run `python <argv…>` for a root through lvim-tasks (with the `python` matcher). `env` optional.
---@param root string
---@param argv string[]
---@param name string
---@param group string
---@param env? table<string, string>
---@return nil
local function run_python(root, argv, name, group, env)
    local cmd = { python_bin(root) }
    vim.list_extend(cmd, argv)
    runner.run("python", { name = name, cmd = cmd, cwd = root, group = group, matcher = "python", env = env })
end

--- The current buffer's file path (absolute), or nil.
---@return string|nil
local function current_file()
    local name = vim.api.nvim_buf_get_name(0)
    return name ~= "" and name or nil
end

--- `:LvimLang run [args]` — run the current file under the venv interpreter. When a run config is
--- active (`.lvim/lang/run.lua`) it supplies the entry point (`module` = `python -m mod`, else
--- `script` = a file), program args and env; extra CLI args append. With no run config: run the
--- current buffer's file.
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    local root = ctx.root or resolve_root()
    local rc = require("lvim-lang.core.runcfg").active(root)
    local argv, env, label = {}, nil, "python run"
    if rc then
        if rc.module then
            argv = { "-m", rc.module }
            label = "python -m " .. rc.module
        else
            argv = { rc.script or current_file() or "." }
            label = "python " .. vim.fs.basename(argv[1])
        end
        vim.list_extend(argv, rc.args or {})
        vim.list_extend(argv, args) -- extra CLI args append
        env = rc.env
    else
        local file = args[1] or current_file()
        if not file then
            vim.notify("lvim-lang: no file to run (open a .py buffer or pass a path)", vim.log.levels.WARN, TITLE)
            return
        end
        argv = { file }
        vim.list_extend(argv, { unpack(args, 2) })
        label = "python " .. vim.fs.basename(file)
    end
    run_python(root, argv, label, "Run", env)
end

--- `:LvimLang run-module <module> [args]` — `python -m <module> [args]`.
---@param args string[]
---@param ctx table
---@return nil
function M.run_module(args, ctx)
    if #args == 0 then
        vim.notify("lvim-lang: usage — :LvimLang run-module <module> [args]", vim.log.levels.INFO, TITLE)
        return
    end
    local argv = { "-m" }
    vim.list_extend(argv, args)
    run_python(ctx.root or resolve_root(), argv, "python -m " .. args[1], "Run")
end

--- `:LvimLang check [args]` — byte-compile the tree (`python -m compileall`) as a fast syntax pass.
--- Not a real build (Python has none) — a cheap "does it all parse" sanity check.
---@param args string[]
---@param ctx table
---@return nil
function M.check(args, ctx)
    local argv = { "-m", "compileall", "-q" }
    vim.list_extend(argv, #args > 0 and args or { "." })
    run_python(ctx.root or resolve_root(), argv, "python -m compileall", "Build")
end

--- The buffer's project root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
