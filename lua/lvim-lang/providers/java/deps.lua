-- lvim-lang.providers.java.deps: dependency inspection through the project's build tool.
-- Gradle and Maven declare dependencies in their build scripts (`build.gradle*` / `pom.xml`), so
-- ADDING / REMOVING a dependency means editing those files by hand — there is no clean, non-
-- destructive CLI verb for it (unlike cargo / npm), and inventing one that rewrites a user's build
-- script would be a kludge. This module therefore exposes the SAFE, read-or-resolve operations:
-- `tree` (the dependency graph), `refresh` (re-resolve, ignoring caches) and `install` (build /
-- install artifacts). Runs land in the lvim-tasks panel (Dependencies group); core.runner runs
-- `:checktime` on exit so an edited lock/metadata reloads in open buffers.
--
---@module "lvim-lang.providers.java.deps"

local runner = require("lvim-lang.core.runner")
local buildtool = require("lvim-lang.providers.java.buildtool")

local TITLE = { title = "lvim-lang" }

local M = {}

--- Resolve the Java project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, {
            "settings.gradle",
            "settings.gradle.kts",
            "build.gradle",
            "build.gradle.kts",
            "pom.xml",
            ".git",
        }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Per-tool argv tails for each dependency action.
---@type table<string, table<"gradle"|"maven", string[]>>
local ACTIONS = {
    tree = { gradle = { "dependencies" }, maven = { "dependency:tree" } },
    refresh = { gradle = { "dependencies", "--refresh-dependencies" }, maven = { "dependency:resolve", "-U" } },
    install = { gradle = { "build" }, maven = { "install" } },
}

-- The `deps` subcommand names (also exposed arg-less as lvim-tasks templates).
local SUBS = { "tree", "refresh", "install" }

--- Run a dependency action for the current buffer's root through lvim-tasks (Dependencies group).
---@param action string
---@param args string[]
---@param ctx table
---@return nil
local function run(action, args, ctx)
    local root = ctx.root or resolve_root()
    local tool = buildtool.detect(root)
    if not tool then
        vim.notify("lvim-lang: no Gradle or Maven project found", vim.log.levels.WARN, TITLE)
        return
    end
    local cmd = buildtool.base(tool, root)
    vim.list_extend(cmd, ACTIONS[action][tool])
    vim.list_extend(cmd, args)
    runner.run("java", {
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
                .. "(add / remove a dependency by editing build.gradle* / pom.xml)",
            vim.log.levels.INFO,
            TITLE
        )
        return
    end
    run(sub, { unpack(args, 2) }, ctx)
end

-- lvim-tasks templates (via the provider's `tasks` field): the arg-less dependency subcommands,
-- each detecting the build tool and applying only when a Gradle/Maven project is present at the
-- resolved root.
---@type table[]
M.templates = {}
for _, action in ipairs(SUBS) do
    M.templates[#M.templates + 1] = {
        name = "java deps " .. action,
        desc = "Java dependencies: " .. action .. " (auto-detected build tool)",
        group = "Dependencies",
        builder = function(ctx)
            local root = (ctx and ctx.root) or resolve_root()
            local tool = buildtool.detect(root)
            if not tool then
                return nil
            end
            local cmd = buildtool.base(tool, root)
            vim.list_extend(cmd, ACTIONS[action][tool])
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
