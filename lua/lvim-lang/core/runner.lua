-- lvim-lang.core.runner: the bridge to lvim-tasks (lvim-lang does NOT run processes itself).
-- One-shot / build / dependency commands become lvim-tasks specs so they inherit that
-- plugin's panel, history, matcher→quickfix and dock for free. (Long-lived structured daemon
-- sessions — flutter run --machine — are the ONE exception and go through core.daemon.)
--
-- Implemented in milestone M4. The stub keeps registry activation safe before then.
--
---@module "lvim-lang.core.runner"

local M = {}

--- Reach lvim-tasks THROUGH the plugin loader, so it is fully initialised before we use it.
--- A plain `require` is NOT enough: lvim-tasks is lazy (`cmd = "LvimTasks"`), and requiring it behind
--- the loader's back skips its `config` hook — so `setup()` never runs, and the module is left half
--- alive: no `User LvimTasksChanged` observer (the panel never repaints — a finished task keeps
--- spinning and the header keeps counting it as running) and no bound highlight factory (every
--- `LvimTasks*` group undefined → a colourless task list beside a coloured output pane). On a
--- published install it is worse: the plugin is not on the runtimepath at all until its trigger
--- fires, so the require simply fails and no provider command can run.
--- `load_plugin` is the loader's documented "I need it at this moment" seam — it does exactly what a
--- trigger does (dependencies + config) and is idempotent. The loader itself is optional: without it
--- the plain require still answers (the plugin is then already on the runtimepath).
---@param reason string  what asked for it, for the loader's load report
---@return table? tasks
local function tasks_module(reason)
    local ok_pack, pack = pcall(require, "lvim-pack")
    if ok_pack and type(pack.load_plugin) == "function" then
        pack.load_plugin("lvim-tasks", reason)
    end
    local ok, tasks = pcall(require, "lvim-tasks")
    return ok and tasks or nil
end

--- Build an lvim-tasks spec from a provider command and run it. A spec may set its own display
--- `group` (Build/Run/Test/Dependencies…); otherwise it defaults to "lvim-lang:<provider>".
--- The task's output panel is REVEALED (unless `spec.show == false`) so the action is visible, and
--- when it finishes the editor's buffers are re-checked (`:checktime`) so any files the task changed
--- on disk (pubspec.lock, generated code, cleaned build dirs…) reload instead of showing stale text.
---@param provider string
---@param spec { name: string, cmd: string[], cwd?: string, env?: table, matcher?: string, group?: string, show?: boolean, hooks?: table }
---@return table|nil task
function M.run(provider, spec)
    local tasks = tasks_module("lvim-lang: " .. provider .. " command")
    if not tasks then
        vim.notify("lvim-lang: lvim-tasks not available", vim.log.levels.WARN, { title = "lvim-lang" })
        return nil
    end
    -- Reload externally-changed buffers when the task exits (nvim never auto-reloads on its own).
    local hooks = spec.hooks or {}
    local prev_exit = hooks.on_exit
    hooks.on_exit = function(task)
        if prev_exit then
            pcall(prev_exit, task)
        end
        vim.schedule(function()
            pcall(vim.cmd, "checktime")
        end)
    end
    local task = tasks.run({
        name = spec.name,
        cmd = spec.cmd,
        cwd = spec.cwd,
        env = spec.env,
        matcher = spec.matcher,
        hooks = hooks,
        group = spec.group or ("lvim-lang:" .. provider),
    })
    -- Reveal the task panel (with the live output) so the action is visible.
    if spec.show ~= false then
        pcall(function()
            tasks.open()
        end)
    end
    return task
end

--- Register a provider's lvim-tasks templates (once per provider).
---@param templates table[]
---@return nil
function M.register_templates(templates)
    local tasks = tasks_module("lvim-lang: task templates")
    if not tasks or type(tasks.register) ~= "function" then
        return
    end
    for _, tpl in ipairs(templates or {}) do
        tasks.register(tpl)
    end
end

return M
