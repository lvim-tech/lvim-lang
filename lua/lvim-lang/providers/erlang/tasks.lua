-- lvim-lang.providers.erlang.tasks: one-shot rebar3 / erlfmt commands run through lvim-tasks.
-- compile / shell / eunit / ct are fire-and-collect (shell is an interactive REPL in the task
-- terminal), so they go through core.runner → lvim-tasks (its panel / history / dock) with the
-- built-in `generic` problem matcher (`file:line:col: message`, which covers the Erlang compiler's
-- `file.erl:Line:Col: error: message` and `file.erl:Line: message` diagnostics). Extra CLI args are
-- appended. `shell` applies the active run configuration (.lvim/lang/run.lua) — its apps / eval /
-- args / env. `fmt` runs erlfmt over the current buffer (format-on-save is handled by efm).
--
---@module "lvim-lang.providers.erlang.tasks"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

local M = {}

--- Resolve the Erlang project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "rebar.config", "erlang.mk", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `rebar3 <argv…>` for a root through lvim-tasks (with the `generic` problem matcher). `env`
--- (optional) is passed to the task process.
---@param root string
---@param argv string[]
---@param name string
---@param group string
---@param env? table<string, string>
---@return nil
local function run_rebar3(root, argv, name, group, env)
    local rebar3 = toolchain.resolve("erlang", "rebar3", root) or "rebar3"
    local cmd = { rebar3 }
    vim.list_extend(cmd, argv)
    runner.run("erlang", { name = name, cmd = cmd, cwd = root, group = group, matcher = "generic", env = env })
end

--- `:LvimLang compile [args]` — `rebar3 compile`.
---@param args string[]
---@param ctx table
---@return nil
function M.compile(args, ctx)
    local argv = { "compile" }
    vim.list_extend(argv, args)
    run_rebar3(ctx.root or resolve_root(), argv, "rebar3 compile", "Build")
end

--- `:LvimLang shell [args]` — `rebar3 shell` (the interactive REPL with the project loaded). Applies
--- the active run config: `apps` (--apps a,b), `eval` (--eval "Expr"), extra `args`, and `env`.
---@param args string[]
---@param ctx table
---@return nil
function M.shell(args, ctx)
    local root = ctx.root or resolve_root()
    local rc = require("lvim-lang.core.runcfg").active(root)
    local argv, env = { "shell" }, nil
    if rc then
        if rc.apps then
            argv[#argv + 1] = "--apps"
            argv[#argv + 1] = type(rc.apps) == "table" and table.concat(rc.apps, ",") or rc.apps
        end
        if rc.eval then
            argv[#argv + 1] = "--eval"
            argv[#argv + 1] = rc.eval
        end
        vim.list_extend(argv, rc.args or {})
        env = rc.env
    end
    vim.list_extend(argv, args)
    run_rebar3(root, argv, "rebar3 shell", "Run", env)
end

--- `:LvimLang eunit [args]` — `rebar3 eunit` (the whole project's EUnit tests).
---@param args string[]
---@param ctx table
---@return nil
function M.eunit(args, ctx)
    local argv = { "eunit" }
    vim.list_extend(argv, args)
    run_rebar3(ctx.root or resolve_root(), argv, "rebar3 eunit", "Test")
end

--- `:LvimLang ct [args]` — `rebar3 ct` (the whole project's Common Test suites).
---@param args string[]
---@param ctx table
---@return nil
function M.ct(args, ctx)
    local argv = { "ct" }
    vim.list_extend(argv, args)
    run_rebar3(ctx.root or resolve_root(), argv, "rebar3 ct", "Test")
end

--- `:LvimLang fmt [args]` — run erlfmt over the current buffer's file (`erlfmt --write <file>`).
--- Rewrites the file on disk; core.runner's `:checktime` on exit reloads the open buffer. (Editor
--- format-on-save is handled separately by efm when erlfmt is the chosen formatter.)
---@param args string[]
---@param ctx table
---@return nil
function M.fmt(args, ctx)
    local root = ctx.root or resolve_root()
    local file = vim.api.nvim_buf_get_name(ctx.bufnr)
    if file == "" then
        vim.notify("lvim-lang: no Erlang file to format (open a .erl file)", vim.log.levels.WARN, TITLE)
        return
    end
    local erlfmt = toolchain.resolve("erlang", "erlfmt", root)
    if not erlfmt then
        vim.notify(
            "lvim-lang: erlfmt not found — installed on demand from the mason registry",
            vim.log.levels.WARN,
            TITLE
        )
        return
    end
    local cmd = { erlfmt, "--write" }
    vim.list_extend(cmd, args)
    cmd[#cmd + 1] = file
    runner.run("erlang", {
        name = "erlfmt " .. vim.fs.basename(file),
        cmd = cmd,
        cwd = root,
        group = "Format",
        matcher = "generic",
    })
end

--- The buffer's project root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
