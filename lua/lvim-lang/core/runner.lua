-- lvim-lang.core.runner: the bridge to lvim-tasks (lvim-lang does NOT run processes itself).
-- One-shot / build / dependency commands become lvim-tasks specs so they inherit that
-- plugin's panel, history, matcher→quickfix and dock for free. (Long-lived structured daemon
-- sessions — flutter run --machine — are the ONE exception and go through core.daemon.)
--
-- Implemented in milestone M4. The stub keeps registry activation safe before then.
--
---@module "lvim-lang.core.runner"

local M = {}

--- Build an lvim-tasks spec from a provider command and run it. A spec may set its own display
--- `group` (Build/Run/Test/Dependencies…); otherwise it defaults to "lvim-lang:<provider>".
---@param provider string
---@param spec { name: string, cmd: string[], cwd?: string, env?: table, matcher?: string, group?: string, hooks?: table }
---@return table|nil task
function M.run(provider, spec)
    local ok, tasks = pcall(require, "lvim-tasks")
    if not ok then
        vim.notify("lvim-lang: lvim-tasks not available", vim.log.levels.WARN, { title = "lvim-lang" })
        return nil
    end
    return tasks.run({
        name = spec.name,
        cmd = spec.cmd,
        cwd = spec.cwd,
        env = spec.env,
        matcher = spec.matcher,
        hooks = spec.hooks,
        group = spec.group or ("lvim-lang:" .. provider),
    })
end

--- Register a provider's lvim-tasks templates (once per provider).
---@param templates table[]
---@return nil
function M.register_templates(templates)
    local ok, tasks = pcall(require, "lvim-tasks")
    if not ok or type(tasks.register) ~= "function" then
        return
    end
    for _, tpl in ipairs(templates or {}) do
        tasks.register(tpl)
    end
end

return M
