-- lvim-lang.providers.scala.deps: dependency inspection through the project's build tool.
-- sbt and mill declare dependencies in their build definition (`build.sbt` / `build.sc`), so ADDING /
-- REMOVING a dependency means editing those files by hand — there is no clean, non-destructive CLI
-- verb for it (unlike cargo / npm), and inventing one that rewrites a user's build definition would be
-- a kludge. This module therefore exposes the SAFE, read-or-resolve operations: `tree` (the resolved
-- dependency graph), `refresh` (re-resolve, ignoring caches) and `install` (publish artifacts to the
-- local repository). Runs land in the lvim-tasks panel (Dependencies group); core.runner runs
-- `:checktime` on exit so an edited lock/metadata reloads in open buffers.
--
-- sbt has first-class verbs for all three (`dependencyTree` is built in since sbt 1.4). mill addresses
-- a MODULE, so its verbs need providers.scala.mill_module. bloop has no dependency verbs (metals /
-- sbt / mill own resolution), so `deps` is a no-op with a notice on a bloop-only project.
--
---@module "lvim-lang.providers.scala.deps"

local runner = require("lvim-lang.core.runner")
local buildtool = require("lvim-lang.providers.scala.buildtool")

local TITLE = { title = "lvim-lang" }

-- Scala's project-root markers (build scripts, then `.git`).
---@type string[]
local ROOT_PATTERNS = { "build.sbt", "build.sc", ".git" }

-- The `deps` subcommand names (also exposed arg-less as lvim-tasks templates).
local SUBS = { "tree", "refresh", "install" }

local M = {}

--- Resolve the Scala project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, ROOT_PATTERNS) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The tail argv for a dependency action on a tool, or nil (after a notice) when the tool cannot
--- express it (bloop has no dep verbs; mill needs a configured module).
---@param tool "sbt"|"mill"|"bloop"
---@param action "tree"|"refresh"|"install"
---@param root string
---@param quiet boolean  suppress the notice (for template builders that just skip)
---@return string[]|nil
local function deps_args(tool, action, root, quiet)
    if tool == "sbt" then
        return ({
            tree = { "dependencyTree" },
            refresh = { "update" },
            install = { "publishLocal" },
        })[action]
    elseif tool == "mill" then
        local mod = buildtool.module(root)
        if not mod then
            if not quiet then
                vim.notify(
                    "lvim-lang: mill dependency tasks need a module — set providers.scala.mill_module",
                    vim.log.levels.WARN,
                    TITLE
                )
            end
            return nil
        end
        return ({
            tree = { mod .. ".ivyDepsTree" },
            refresh = { mod .. ".compile" }, -- forces a fresh dependency resolution
            install = { mod .. ".publishLocal" },
        })[action]
    end
    -- bloop
    if not quiet then
        vim.notify(
            "lvim-lang: bloop has no dependency verbs — inspect deps via sbt / mill (or metals)",
            vim.log.levels.INFO,
            TITLE
        )
    end
    return nil
end

--- Run a dependency action for the current buffer's root through lvim-tasks (Dependencies group).
---@param action string
---@param args string[]
---@param ctx table
---@return nil
local function run(action, args, ctx)
    local root = ctx.root or resolve_root()
    local tool = buildtool.detect(root)
    if not tool then
        vim.notify("lvim-lang: no sbt / mill / bloop project found", vim.log.levels.WARN, TITLE)
        return
    end
    local tail = deps_args(tool, action, root, false)
    if not tail then
        return
    end
    local cmd = buildtool.base(tool, root)
    vim.list_extend(cmd, tail)
    vim.list_extend(cmd, args)
    runner.run("scala", {
        name = vim.fs.basename(cmd[1]) .. " " .. action,
        cmd = cmd,
        cwd = root,
        group = "Dependencies",
        matcher = "generic",
    })
end

--- The `deps` subcommand names (for command completion).
---@return string[]
function M.subs()
    return vim.deepcopy(SUBS)
end

--- `:LvimLang deps <tree|refresh|install> [args]`.
---@param args string[]
---@param ctx table
---@return nil
function M.command(args, ctx)
    local sub = args[1] or "tree"
    if not vim.tbl_contains(SUBS, sub) then
        vim.notify(
            "lvim-lang: usage — :LvimLang deps <"
                .. table.concat(SUBS, "|")
                .. ">  "
                .. "(add / remove a dependency by editing build.sbt / build.sc)",
            vim.log.levels.INFO,
            TITLE
        )
        return
    end
    run(sub, { unpack(args, 2) }, ctx)
end

-- lvim-tasks templates (via the provider's `tasks` field): the arg-less dependency subcommands, each
-- detecting the build tool and applying only when the resolved tool can express the action.
---@type table[]
M.templates = {}
for _, action in ipairs(SUBS) do
    M.templates[#M.templates + 1] = {
        name = "scala deps " .. action,
        desc = "Scala dependencies: " .. action .. " (auto-detected build tool)",
        group = "Dependencies",
        builder = function(ctx)
            local root = (ctx and ctx.root) or resolve_root()
            local tool = buildtool.detect(root)
            if not tool then
                return nil
            end
            local tail = deps_args(tool, action, root, true)
            if not tail then
                return nil
            end
            local cmd = buildtool.base(tool, root)
            vim.list_extend(cmd, tail)
            return {
                name = vim.fs.basename(cmd[1]) .. " " .. action,
                cmd = cmd,
                cwd = root,
                group = "Dependencies",
                matcher = "generic",
            }
        end,
    }
end

return M
