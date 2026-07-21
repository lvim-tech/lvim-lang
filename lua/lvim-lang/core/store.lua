-- lvim-lang.core.store: the single lvim-utils.store handle shared across the plugin.
-- One json store named "lvim-lang" holds every persisted field (the per-root device choice, the
-- per-root selected run config, …), so the various provider modules don't each open a rival
-- handle to the same file. Guarded — returns nil when lvim-utils.store is unavailable, and every
-- caller degrades to session-only state.
--
---@module "lvim-lang.core.store"

local M = {}

---@type table|false|nil  the live store handle, false when unavailable, nil before first use
local db = nil

--- The shared store handle, or nil when persistence is unavailable.
---@return table|nil
function M.get()
    if db == nil then
        local ok, store = pcall(require, "lvim-utils.store")
        if ok then
            local ok2, handle = pcall(store.new, {
                backend = "json",
                name = "lvim-lang",
                fields = { devices = {}, run_configs = {} },
            })
            db = (ok2 and handle) or false
        else
            db = false
        end
    end
    return db or nil
end

return M
