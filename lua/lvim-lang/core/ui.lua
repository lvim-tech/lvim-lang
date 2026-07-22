-- lvim-lang.core.ui: shared UI helpers, all routed through the canonical lvim-ui primitives.
-- lvim-lang never opens a raw float or calls vim.ui.select: device / target / command pickers
-- go through lvim-ui.select, the run-flags menu through lvim-ui.transient, the help window
-- follows the outline show_help canon, and statusline getters aggregate provider segments.
--
-- Implemented across M6 (pickers) / M9 (transient, statusline). The stub documents the contract.
--
---@module "lvim-lang.core.ui"

local M = {}

--- Pick one item through the canonical centered picker.
---@param opts { title: string, items: table[], current?: integer }
---@param cb fun(item: table|nil, index: integer|nil)
---@return nil
function M.pick(opts, cb)
    local ok, ui = pcall(require, "lvim-ui")
    if not ok then
        return
    end
    ui.select({
        title = opts.title,
        items = opts.items,
        current_item = opts.current,
        callback = function(confirmed, index)
            cb(confirmed and opts.items[index] or nil, confirmed and index or nil)
        end,
    })
end

--- A SHARED running-task indicator for a provider's root: if any lvim-tasks task is currently
--- running with this root as its cwd, return "<run icon> <task name>" (the provider's own `run`
--- icon), else "". Language-agnostic — every provider gets the same live indicator with no
--- per-provider code. Refreshes with the statusline on the `User LvimTasksChanged` event.
---@param name string  provider name (for its run icon)
---@param root string
---@return string
function M.running_indicator(name, root)
    local ok, tasks = pcall(require, "lvim-tasks")
    if not ok or type(tasks.list) ~= "function" then
        return ""
    end
    local ic = (require("lvim-lang.config").providers[name] or {}).icons or {}
    for _, t in ipairs(tasks.list()) do
        if t.status == "running" and t.spec and t.spec.cwd == root then
            return (ic.run or "󰐊") .. " " .. (t.spec.name or "running")
        end
    end
    return ""
end

--- The statusline segment for a buffer: the active provider's segment PLUS the shared running-task
--- indicator (both empty when there is no provider / no running task, or when statusline segments
--- are disabled). The running indicator is added HERE so every provider gets it consistently.
---@param bufnr? integer
---@return string
function M.statusline(bufnr)
    local config = require("lvim-lang.config")
    if config.statusline == false then
        return ""
    end
    local provider, root = require("lvim-lang.registry").for_buffer(bufnr)
    if not (provider and root) then
        return ""
    end
    local segment = ""
    if provider.statusline then
        local ok, seg = pcall(provider.statusline, root)
        segment = (ok and type(seg) == "string") and seg or ""
    end
    local running = M.running_indicator(provider.name, root)
    if running ~= "" then
        segment = segment ~= "" and (segment .. "  " .. running) or running
    end
    return segment
end

return M
