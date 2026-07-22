-- lvim-lang.providers.python.deps: Python dependency management, run through lvim-tasks.
-- Python has four common managers; the RIGHT one is detected from the project (pyproject
-- `[tool.poetry]` / `[tool.uv]`, `uv.lock`, `Pipfile`, else pip) unless pinned via
-- `providers.python.dependency_manager`. add / remove / update / install / lock / tree map to each
-- manager's own verbs from ONE spec table, so runs land in the lvim-tasks panel / history / dock with
-- the correct binary (pip through the venv interpreter as `python -m pip`; poetry / uv / pipenv on
-- PATH) and cwd (the project root). core.runner runs `:checktime` on exit, so an edited
-- pyproject.toml / lock file reloads in open buffers.
--
---@module "lvim-lang.providers.python.deps"

local config = require("lvim-lang.config")
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
        return vim.fs.root(buf, { "pyproject.toml", "setup.py", "requirements.txt", "Pipfile", ".git" })
            or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The venv interpreter for a root (else `python3`) — pip runs as `python -m pip`.
---@param root string
---@return string
local function python_bin(root)
    return toolchain.resolve("python", "python", root) or "python3"
end

--- Does `root/pyproject.toml` contain the TOML table header `[tool.<name>]`?
---@param root string
---@param name string
---@return boolean
local function pyproject_has(root, name)
    local path = vim.fs.joinpath(root, "pyproject.toml")
    if vim.fn.filereadable(path) ~= 1 then
        return false
    end
    for _, line in ipairs(vim.fn.readfile(path)) do
        if line:match("^%s*%[tool%." .. name .. "%]") then
            return true
        end
    end
    return false
end

--- Per-manager verbs. Each entry: `marker` (the file whose presence means "this manager", gating the
--- arg-less templates), `base(root)` (the leading command), and `actions` (action → a mapper from
--- the user args to the argv tail).
---@type table<string, table>
local MANAGERS = {
    pip = {
        marker = "requirements.txt",
        base = function(root)
            return { python_bin(root), "-m", "pip" }
        end,
        actions = {
            add = function(a)
                return vim.list_extend({ "install" }, a)
            end,
            remove = function(a)
                return vim.list_extend({ "uninstall", "-y" }, a)
            end,
            update = function(a)
                return vim.list_extend({ "install", "--upgrade" }, a)
            end,
            install = function(_)
                return { "install", "-r", "requirements.txt" }
            end,
            tree = function(_)
                return { "list" }
            end,
            lock = function(_)
                return { "freeze" }
            end,
        },
    },
    poetry = {
        marker = "pyproject.toml",
        base = function(_)
            return { "poetry" }
        end,
        actions = {
            add = function(a)
                return vim.list_extend({ "add" }, a)
            end,
            remove = function(a)
                return vim.list_extend({ "remove" }, a)
            end,
            update = function(a)
                return vim.list_extend({ "update" }, a)
            end,
            install = function(_)
                return { "install" }
            end,
            tree = function(_)
                return { "show", "--tree" }
            end,
            lock = function(_)
                return { "lock" }
            end,
        },
    },
    uv = {
        marker = "uv.lock",
        base = function(_)
            return { "uv" }
        end,
        actions = {
            add = function(a)
                return vim.list_extend({ "add" }, a)
            end,
            remove = function(a)
                return vim.list_extend({ "remove" }, a)
            end,
            update = function(a)
                -- uv upgrades through the lock: a single package, or every package.
                return #a > 0 and vim.list_extend({ "lock", "--upgrade-package" }, a) or { "lock", "--upgrade" }
            end,
            install = function(_)
                return { "sync" }
            end,
            tree = function(_)
                return { "tree" }
            end,
            lock = function(_)
                return { "lock" }
            end,
        },
    },
    pipenv = {
        marker = "Pipfile",
        base = function(_)
            return { "pipenv" }
        end,
        actions = {
            add = function(a)
                return vim.list_extend({ "install" }, a)
            end,
            remove = function(a)
                return vim.list_extend({ "uninstall" }, a)
            end,
            update = function(a)
                return vim.list_extend({ "update" }, a)
            end,
            install = function(_)
                return { "install" }
            end,
            tree = function(_)
                return { "graph" }
            end,
            lock = function(_)
                return { "lock" }
            end,
        },
    },
}

--- The dependency manager for a root: the pinned `dependency_manager` (unless "auto"), else detected
--- — poetry / uv (pyproject table or lock), pipenv (Pipfile), else pip.
---@param root string
---@return string
function M.detect(root)
    local pinned = (config.providers.python or {}).dependency_manager
    if type(pinned) == "string" and pinned ~= "auto" and MANAGERS[pinned] then
        return pinned
    end
    if pyproject_has(root, "poetry") then
        return "poetry"
    end
    if pyproject_has(root, "uv") or vim.fn.filereadable(vim.fs.joinpath(root, "uv.lock")) == 1 then
        return "uv"
    end
    if vim.fn.filereadable(vim.fs.joinpath(root, "Pipfile")) == 1 then
        return "pipenv"
    end
    return "pip"
end

--- Build the lvim-tasks command for a (manager, action) at `root`, or nil for an unknown action.
---@param manager string
---@param action string
---@param root string
---@param args string[]
---@return string[]|nil cmd, string|nil label
local function build(manager, action, root, args)
    local m = MANAGERS[manager]
    local mk = m and m.actions[action]
    if not mk then
        return nil
    end
    local cmd = m.base(root)
    vim.list_extend(cmd, mk(args))
    return cmd, manager .. " " .. action
end

--- Run a (manager, action) for the current buffer's root through lvim-tasks (Dependencies group).
---@param action string
---@param args string[]
---@param ctx table
---@return nil
local function run(action, args, ctx)
    local root = ctx.root or resolve_root()
    local manager = M.detect(root)
    local cmd, label = build(manager, action, root, args)
    if not (cmd and label) then
        return
    end
    runner.run("python", { name = label, cmd = cmd, cwd = root, group = "Dependencies", matcher = "python" })
end

--- `:LvimLang add <pkg…>` — add a dependency (poetry/uv add · pipenv/pip install).
---@param args string[]
---@param ctx table
---@return nil
function M.add(args, ctx)
    if #args == 0 then
        vim.notify("lvim-lang: usage — :LvimLang add <package…>", vim.log.levels.INFO, TITLE)
        return
    end
    run("add", args, ctx)
end

--- `:LvimLang remove <pkg…>` — remove a dependency.
---@param args string[]
---@param ctx table
---@return nil
function M.remove(args, ctx)
    if #args == 0 then
        vim.notify("lvim-lang: usage — :LvimLang remove <package…>", vim.log.levels.INFO, TITLE)
        return
    end
    run("remove", args, ctx)
end

--- `:LvimLang update [pkg…]` — update dependencies (all, or the named ones).
---@param args string[]
---@param ctx table
---@return nil
function M.update(args, ctx)
    run("update", args, ctx)
end

-- The `deps` subcommands (also exposed arg-less).
local SUBS = { "install", "update", "tree", "lock" }

--- The `deps` subcommand names (for command completion).
---@return string[]
function M.subs()
    return vim.deepcopy(SUBS)
end

--- The `:LvimLang deps <install|update|tree|lock> [args]` command.
---@param args string[]
---@param ctx table
---@return nil
function M.command(args, ctx)
    local sub = args[1] or "install"
    if not vim.tbl_contains(SUBS, sub) then
        vim.notify(
            "lvim-lang: usage — :LvimLang deps <" .. table.concat(SUBS, "|") .. ">",
            vim.log.levels.INFO,
            TITLE
        )
        return
    end
    run(sub, { unpack(args, 2) }, ctx)
end

-- lvim-tasks templates (via the provider's `tasks` field): the arg-less subcommands, each detecting
-- the manager and applying only when its marker file is present at the resolved root.
---@type table[]
M.templates = {}
for _, action in ipairs({ "install", "lock", "tree" }) do
    M.templates[#M.templates + 1] = {
        name = "python deps " .. action,
        desc = "Python dependencies: " .. action .. " (auto-detected manager)",
        group = "Dependencies",
        builder = function(ctx)
            local root = (ctx and ctx.root) or resolve_root()
            local manager = M.detect(root)
            local marker = MANAGERS[manager].marker
            if vim.fn.filereadable(vim.fs.joinpath(root, marker)) ~= 1 then
                return nil
            end
            local cmd, label = build(manager, action, root, {})
            if not cmd then
                return nil
            end
            return { name = label, cmd = cmd, cwd = root, group = "Dependencies", matcher = "python" }
        end,
    }
end

return M
