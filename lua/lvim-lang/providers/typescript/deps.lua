-- lvim-lang.providers.typescript.deps: JS/TS dependency management, run through lvim-tasks.
-- The package manager is detected per project (providers.typescript.pm); add / remove / update /
-- install / outdated map to each manager's own verbs (npm uses install/uninstall, the others use
-- add/remove; yarn upgrades with `upgrade`). Runs land in the lvim-tasks panel / history / dock with
-- the correct binary and cwd (the project root). core.runner runs `:checktime` on exit, so an edited
-- package.json / lockfile reloads in open buffers.
--
---@module "lvim-lang.providers.typescript.deps"

local runner = require("lvim-lang.core.runner")
local pm = require("lvim-lang.providers.typescript.pm")

local TITLE = { title = "lvim-lang" }

local M = {}

-- Per-manager verb for each action (nil = unsupported).
---@type table<string, table<string, string>>
local VERBS = {
    npm = { add = "install", remove = "uninstall", update = "update", install = "install", outdated = "outdated" },
    pnpm = { add = "add", remove = "remove", update = "update", install = "install", outdated = "outdated" },
    yarn = { add = "add", remove = "remove", update = "upgrade", install = "install", outdated = "outdated" },
    bun = { add = "add", remove = "remove", update = "update", install = "install", outdated = "outdated" },
}

--- Resolve the JS/TS project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "package.json", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run a (manager, action) with `args` for the current buffer's root through lvim-tasks.
---@param action string
---@param args string[]
---@param ctx table
---@return nil
local function run(action, args, ctx)
    local root = ctx.root or resolve_root()
    local manager = pm.detect(root)
    local verb = (VERBS[manager] or VERBS.npm)[action]
    if not verb then
        vim.notify(("lvim-lang: %s does not support `%s`"):format(manager, action), vim.log.levels.WARN, TITLE)
        return
    end
    local cmd = { manager, verb }
    vim.list_extend(cmd, args)
    runner.run("typescript", {
        name = manager .. " " .. verb,
        cmd = cmd,
        cwd = root,
        group = "Dependencies",
        matcher = "typescript",
    })
end

--- `:LvimLang add <package…>` — add a dependency (npm install · pnpm/yarn/bun add).
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

--- `:LvimLang remove <package…>` — remove a dependency.
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

--- `:LvimLang update [package…]` — update dependencies (all, or the named ones).
---@param args string[]
---@param ctx table
---@return nil
function M.update(args, ctx)
    run("update", args, ctx)
end

-- The `deps` subcommands.
local SUBS = { "install", "update", "outdated" }

--- The `deps` subcommand names (for command completion).
---@return string[]
function M.subs()
    return vim.deepcopy(SUBS)
end

--- The `:LvimLang deps <install|update|outdated> [args]` command.
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

return M
