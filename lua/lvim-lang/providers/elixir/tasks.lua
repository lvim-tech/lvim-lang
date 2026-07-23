-- lvim-lang.providers.elixir.tasks: one-shot `mix` / `iex` commands run through lvim-tasks.
-- compile / run / iex / format / credo are fire-and-collect, so they go through core.runner →
-- lvim-tasks (its panel / history / dock) with the built-in `generic` problem matcher
-- (`file:line:col: message`, which covers the Elixir compiler's `lib/foo.ex:12: …` diagnostics and
-- credo's flycheck output). The `mix` binary is resolved per project through core.toolchain (honouring
-- the version manager). Extra command-line args are appended (e.g. `:LvimLang compile --force`).
--
---@module "lvim-lang.providers.elixir.tasks"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

local M = {}

--- Resolve the Elixir project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "mix.exs", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `mix <argv…>` for a root through lvim-tasks (with the `generic` problem matcher). `env`
--- (optional) is passed to the task process.
---@param root string
---@param argv string[]
---@param name string
---@param group string
---@param env? table<string, string>
---@return nil
local function run_mix(root, argv, name, group, env)
    local mix = toolchain.resolve("elixir", "mix", root) or "mix"
    local cmd = { mix }
    vim.list_extend(cmd, argv)
    runner.run("elixir", { name = name, cmd = cmd, cwd = root, group = group, matcher = "generic", env = env })
end

--- `:LvimLang compile [args]` — `mix compile`.
---@param args string[]
---@param ctx table
---@return nil
function M.compile(args, ctx)
    local argv = { "compile" }
    vim.list_extend(argv, args)
    run_mix(ctx.root or resolve_root(), argv, "mix compile", "Build")
end

--- `:LvimLang run [args]` — `mix run`. When a run config is active (`.lvim/lang/run.lua`) it supplies
--- the mix task, its args and env; extra CLI args append.
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    local root = ctx.root or resolve_root()
    local rc = require("lvim-lang.core.runcfg").active(root)
    local argv, env = {}, nil
    if rc then
        -- A run config may drive any mix task (e.g. `phx.server`); default to `run`.
        argv[#argv + 1] = rc.task or "run"
        vim.list_extend(argv, rc.args or {})
        env = rc.env
    else
        argv[#argv + 1] = "run"
    end
    vim.list_extend(argv, args)
    run_mix(root, argv, "mix " .. (argv[1] or "run"), "Run", env)
end

--- `:LvimLang iex [args]` — `iex -S mix` (an interactive shell inside the project). Runs through the
--- lvim-tasks pty; extra args append (e.g. `:LvimLang iex --sname node1`).
---@param args string[]
---@param ctx table
---@return nil
function M.iex(args, ctx)
    local root = ctx.root or resolve_root()
    local iex = toolchain.resolve("elixir", "iex", root) or "iex"
    local cmd = { iex }
    vim.list_extend(cmd, args)
    vim.list_extend(cmd, { "-S", "mix" })
    runner.run("elixir", { name = "iex -S mix", cmd = cmd, cwd = root, group = "Run", matcher = "generic" })
end

--- `:LvimLang format [args]` — `mix format` over the project (reads `.formatter.exs`). Rewrites files
--- on disk; core.runner's `:checktime` on exit reloads open buffers.
---@param args string[]
---@param ctx table
---@return nil
function M.format(args, ctx)
    local argv = { "format" }
    vim.list_extend(argv, args)
    run_mix(ctx.root or resolve_root(), argv, "mix format", "Format")
end

--- `:LvimLang credo [args]` — `mix credo` (static analysis / linting). Defaults to `--strict` for the
--- richer rule set when no args are given; the `credo` dependency must be in the project's mix.exs.
---@param args string[]
---@param ctx table
---@return nil
function M.credo(args, ctx)
    local argv = { "credo" }
    vim.list_extend(argv, #args > 0 and args or { "--strict" })
    run_mix(ctx.root or resolve_root(), argv, "mix credo", "Lint")
end

--- The buffer's project root (exposed so command wrappers / dap share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
