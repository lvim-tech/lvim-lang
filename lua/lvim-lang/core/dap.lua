-- lvim-lang.core.dap: a thin bridge to lvim-dap (lvim-lang owns no debugger engine).
-- The bulk of registration is automatic: a provider's server-config carries a `dap` field
-- ({ adapters, configurations }) and lvim-ls registers it with lvim-dap on attach. This module
-- only adds the extra seam that is NOT static: a DYNAMIC configuration provider, for launch
-- configs that depend on live state (the selected device, the active run config's flavor/target).
--
---@module "lvim-lang.core.dap"

local M = {}

--- Register a dynamic dap configuration provider (lvim-dap's register_provider seam). `fn(bufnr)`
--- returns extra configurations gathered alongside the statically-registered ones. Idempotent by
--- id; degrades to a no-op when lvim-dap is unavailable.
---@param id string
---@param fn fun(bufnr: integer): table[]
---@return nil
function M.register_configs(id, fn)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok or type(dap.register_provider) ~= "function" then
        return
    end
    dap.register_provider(id, fn)
end

return M
