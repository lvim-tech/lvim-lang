-- lvim-lang.providers.ruby.tasks: one-shot ruby / rake / rubocop commands run through lvim-tasks.
-- run (the current file) / rake / rubocop / rubocop-fix are fire-and-collect, so they go through
-- core.runner → lvim-tasks (its panel / history / dock) with the built-in `generic` problem matcher
-- (`file:line:col: message`, which covers ruby's `file.rb:line:` backtraces and rubocop's emacs
-- format). Commands that touch the bundle are prefixed with `bundle exec` when the project has a
-- Gemfile + bundler, so they run against the project's locked gems. Extra CLI args are appended.
--
---@module "lvim-lang.providers.ruby.tasks"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

local M = {}

--- Resolve the Ruby project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "Gemfile", "Rakefile", ".ruby-version", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The `bundle exec` prefix for a root (when a Gemfile + bundler are present), else an empty list —
--- so a bundled project runs a tool against its locked gems, and a bare project runs it directly.
---@param root string
---@return string[]
local function bundle_prefix(root)
    if vim.fn.filereadable(vim.fs.joinpath(root, "Gemfile")) == 1 then
        local bundle = toolchain.resolve("ruby", "bundle", root)
        if bundle then
            return { bundle, "exec" }
        end
    end
    return {}
end

--- Run an argv for a root through lvim-tasks (with the `generic` problem matcher). `env` (optional)
--- is passed to the task process.
---@param root string
---@param cmd string[]
---@param name string
---@param group string
---@param env? table<string, string>
---@return nil
local function run_cmd(root, cmd, name, group, env)
    runner.run("ruby", { name = name, cmd = cmd, cwd = root, group = group, matcher = "generic", env = env })
end

--- `:LvimLang run [args]` — run the current file with `ruby` (`bundle exec ruby` in a bundled
--- project). When a run config is active (`.lvim/lang/run.lua`) it supplies the script, program args
--- and env; extra CLI args append.
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    local root = ctx.root or resolve_root()
    local ruby = toolchain.resolve("ruby", "ruby", root) or "ruby"
    local rc = require("lvim-lang.core.runcfg").active(root)
    local cmd = bundle_prefix(root)
    cmd[#cmd + 1] = ruby
    local env
    local script = vim.api.nvim_buf_get_name(ctx.bufnr)
    if rc then
        env = rc.env
        script = rc.script or script
    end
    if script == "" then
        vim.notify(
            "lvim-lang: no ruby file to run (open a .rb file or set a run config script)",
            vim.log.levels.WARN,
            TITLE
        )
        return
    end
    cmd[#cmd + 1] = script
    if rc and rc.args then
        vim.list_extend(cmd, rc.args)
    end
    vim.list_extend(cmd, args)
    run_cmd(root, cmd, "ruby " .. vim.fs.basename(script), "Run", env)
end

--- `:LvimLang rake [task] [args]` — `rake <task>` (`bundle exec rake` in a bundled project).
---@param args string[]
---@param ctx table
---@return nil
function M.rake(args, ctx)
    local root = ctx.root or resolve_root()
    local prefix = bundle_prefix(root)
    local cmd = prefix
    if #prefix > 0 then
        cmd[#cmd + 1] = "rake"
    else
        cmd[#cmd + 1] = toolchain.resolve("ruby", "rake", root) or "rake"
    end
    vim.list_extend(cmd, args)
    run_cmd(root, cmd, "rake" .. (args[1] and (" " .. args[1]) or ""), "Build")
end

--- `:LvimLang rubocop [args]` — run rubocop over the project (Lint group).
---@param args string[]
---@param ctx table
---@return nil
function M.rubocop(args, ctx)
    local root = ctx.root or resolve_root()
    local prefix = bundle_prefix(root)
    local cmd = prefix
    if #prefix > 0 then
        cmd[#cmd + 1] = "rubocop"
    else
        cmd[#cmd + 1] = toolchain.resolve("ruby", "rubocop", root) or "rubocop"
    end
    vim.list_extend(cmd, args)
    run_cmd(root, cmd, "rubocop", "Lint")
end

--- `:LvimLang rubocop-fix [args]` — `rubocop -A` (autocorrect, including unsafe). Rewrites files on
--- disk; core.runner's `:checktime` on exit reloads open buffers.
---@param args string[]
---@param ctx table
---@return nil
function M.rubocop_fix(args, ctx)
    local root = ctx.root or resolve_root()
    local prefix = bundle_prefix(root)
    local cmd = prefix
    if #prefix > 0 then
        cmd[#cmd + 1] = "rubocop"
    else
        cmd[#cmd + 1] = toolchain.resolve("ruby", "rubocop", root) or "rubocop"
    end
    vim.list_extend(cmd, #args > 0 and args or { "-A" })
    run_cmd(root, cmd, "rubocop -A", "Lint")
end

--- The buffer's project root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
