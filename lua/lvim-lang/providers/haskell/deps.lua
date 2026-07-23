-- lvim-lang.providers.haskell.deps: dependency inspection / resolution through the project's build tool.
-- A package's dependencies are declared in its `*.cabal` `build-depends` (or a hpack `package.yaml`),
-- so ADDING / REMOVING one means editing those files by hand — there is no clean, non-destructive CLI
-- verb for it (unlike cargo / npm), and rewriting a user's build file would be a kludge. This module
-- therefore exposes the SAFE, read-or-resolve operations: `resolve` (fetch + build ONLY the
-- dependencies), `freeze` (pin an exact plan — Cabal), `list` (the resolved dependency list — Stack)
-- and `outdated` (Cabal). Each maps to whichever verb the detected tool supports; an unsupported
-- (tool, action) reports how that tool handles it instead. Runs land in the lvim-tasks panel
-- (Dependencies group); core.runner runs `:checktime` on exit so an edited plan reloads in buffers.
--
---@module "lvim-lang.providers.haskell.deps"

local runner = require("lvim-lang.core.runner")
local buildtool = require("lvim-lang.providers.haskell.buildtool")

local TITLE = { title = "lvim-lang" }

local M = {}

--- Resolve the Haskell project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    return buildtool.root_of(vim.api.nvim_get_current_buf())
end

--- Per-tool argv tails for each dependency action. A `nil` for a (tool, action) means that tool has
--- no clean verb for it (reported with the tool's actual mechanism).
---@type table<string, table<"stack"|"cabal", string[]|nil>>
local ACTIONS = {
    resolve = { stack = { "build", "--only-dependencies" }, cabal = { "build", "--only-dependencies" } },
    freeze = { cabal = { "freeze" } }, -- Stack pins via its resolver (stack.yaml) — no freeze verb.
    list = { stack = { "ls", "dependencies" } }, -- Cabal has no first-party flat list (needs cabal-plan).
    outdated = { cabal = { "outdated" } }, -- Stack surfaces this through `stack ls dependencies` + its resolver.
}

-- How each tool handles an action it has no verb for (shown instead of a no-op).
---@type table<string, table<"stack"|"cabal", string>>
local UNSUPPORTED = {
    freeze = { stack = "Stack pins the exact plan through its resolver in stack.yaml — no freeze command." },
    list = { cabal = "Cabal has no first-party flat dependency list — use `cabal-plan` (external)." },
    outdated = { stack = "Stack's versions follow its resolver; `:LvimLang deps list` shows the resolved set." },
}

-- The `deps` subcommand names (the safe read/resolve ops; `resolve` is also an lvim-tasks template).
---@type string[]
local SUBS = { "resolve", "freeze", "list", "outdated" }

--- Run a dependency action for a root through lvim-tasks (Dependencies group).
---@param action string
---@param args string[]
---@param ctx table
---@return nil
local function run(action, args, ctx)
    local root = ctx.root or resolve_root()
    local tool = buildtool.detect(root)
    if not tool then
        vim.notify("lvim-lang: no Stack or Cabal project found", vim.log.levels.WARN, TITLE)
        return
    end
    local argv = ACTIONS[action][tool]
    if not argv then
        vim.notify(
            "lvim-lang: `"
                .. action
                .. "` — "
                .. ((UNSUPPORTED[action] or {})[tool] or (tool .. " has no such command")),
            vim.log.levels.INFO,
            TITLE
        )
        return
    end
    local cmd = buildtool.base(tool, root)
    vim.list_extend(cmd, argv)
    vim.list_extend(cmd, args)
    runner.run("haskell", {
        name = tool .. " " .. action,
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

--- `:LvimLang deps <resolve|freeze|list|outdated> [args]`.
---@param args string[]
---@param ctx table
---@return nil
function M.command(args, ctx)
    local sub = args[1] or "resolve"
    if not vim.tbl_contains(SUBS, sub) then
        vim.notify(
            "lvim-lang: usage — :LvimLang deps <"
                .. table.concat(SUBS, "|")
                .. ">  (add / remove a dependency by editing the *.cabal build-depends / package.yaml)",
            vim.log.levels.INFO,
            TITLE
        )
        return
    end
    run(sub, { unpack(args, 2) }, ctx)
end

-- lvim-tasks templates (via the provider's `tasks` field): the always-safe `resolve` action, applying
-- only when a Stack/Cabal project is present at the resolved root.
---@type table[]
M.templates = {
    {
        name = "haskell deps resolve",
        desc = "Haskell dependencies: fetch + build only the dependencies (auto-detected build tool)",
        group = "Dependencies",
        builder = function(ctx)
            local root = (ctx and ctx.root) or resolve_root()
            local tool = buildtool.detect(root)
            if not tool then
                return nil
            end
            local cmd = buildtool.base(tool, root)
            vim.list_extend(cmd, ACTIONS.resolve[tool])
            return { name = tool .. " resolve", cmd = cmd, cwd = root, group = "Dependencies", matcher = "generic" }
        end,
    },
}

return M
