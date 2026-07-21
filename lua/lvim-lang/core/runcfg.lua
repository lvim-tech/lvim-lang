-- lvim-lang.core.runcfg: per-project run configurations.
-- Reads named run configs from the unified project namespace (config.project.dir ..
-- config.project.run_file, i.e. ".lvim/lang/run.lua" — a pure-data Lua file returning a list of
-- named config tables). The chosen config's NAME is remembered per root through the shared store,
-- so `active(root)` returns the currently-selected config. This module is language-agnostic: a
-- provider interprets a config table into its own run arguments.
--
---@module "lvim-lang.core.runcfg"

local config = require("lvim-lang.config")
local ui = require("lvim-lang.core.ui")

local M = {}

--- Absolute path to a root's run-config file under the unified ".lvim" namespace.
---@param root string
---@return string
function M.path(root)
    return table.concat({ root, config.project.dir, config.project.run_file }, "/")
end

--- List the named run configurations for a root (empty when the file is absent / invalid).
--- The file is pure data — loaded in a protected call, never trusted to run side effects.
---@param root string
---@return table[]
function M.list(root)
    local path = M.path(root)
    if vim.fn.filereadable(path) ~= 1 then
        return {}
    end
    local ok, chunk = pcall(dofile, path)
    if ok and vim.islist(chunk) then
        return chunk
    end
    return {}
end

--- Persist the selected run-config NAME for a root (session + disk).
---@param root string
---@param name string|nil  nil clears the selection
---@return nil
function M.select(root, name)
    local db = require("lvim-lang.core.store").get()
    if not db then
        return
    end
    local all = db.run_configs or {}
    all[root] = name
    db.run_configs = all
end

--- The currently-active run config table for a root (the persisted selection, else the first
--- config in the file, else nil).
---@param root string
---@return table|nil
function M.active(root)
    local list = M.list(root)
    if #list == 0 then
        return nil
    end
    local db = require("lvim-lang.core.store").get()
    local name = db and db.run_configs and db.run_configs[root]
    if name then
        for _, cfg in ipairs(list) do
            if cfg.name == name then
                return cfg
            end
        end
    end
    return list[1]
end

--- Pick a run configuration through the canonical picker; on confirm it becomes the active one.
---@param root string
---@param cb? fun(cfg: table|nil)
---@return nil
function M.pick(root, cb)
    local list = M.list(root)
    if #list == 0 then
        vim.notify(
            "lvim-lang: no run configs — create " .. M.path(root),
            vim.log.levels.INFO,
            { title = "lvim-lang" }
        )
        if cb then
            cb(nil)
        end
        return
    end
    local active = M.active(root)
    local icon = (config.icons and config.icons.run_config) or "󰐊"
    local items, current = {}, nil
    for i, cfg in ipairs(list) do
        items[i] = { label = cfg.name or ("config " .. i), icon = icon, cfg = cfg }
        if active and active.name == cfg.name then
            current = i
        end
    end
    ui.pick({ title = "Run configuration", items = items, current = current }, function(item)
        if not item then
            if cb then
                cb(nil)
            end
            return
        end
        M.select(root, item.cfg.name)
        vim.notify("lvim-lang: run config → " .. (item.cfg.name or "?"), vim.log.levels.INFO, { title = "lvim-lang" })
        if cb then
            cb(item.cfg)
        end
    end)
end

--- Command adapter (`:LvimLang config`): pick the active run configuration for the buffer's root.
---@param _args string[]
---@param ctx table  { provider, root, bufnr }
---@return nil
function M.command(_args, ctx)
    M.pick(ctx.root)
end

return M
