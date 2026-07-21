-- lvim-lang.state: runtime-only state, keyed by project root.
-- Everything here is derived at run time and must NEVER hold configuration — that lives in
-- lvim-lang.config. Kept as one module-level table so any core/provider module can read the
-- same live picture (active daemon sessions, resolved toolchains, the selected device / run
-- config per root). Cleared entries are the caller's responsibility on session end.
--
---@module "lvim-lang.state"

---@class LvimLangState
---@field roots      table<string, boolean>        Roots already activated once (dedup guard)
---@field toolchains table<string, table<string, string>>  root → ("provider:tool" → resolved binary path)
---@field sessions   table<string, table>          root → live daemon session handle
---@field devices    table<string, table[]>        root → last-known device list (cache)
---@field selected   table<string, table>          root → { device?, run_config? } current choices
---@field devtools   table<string, table>          root → live DevTools server session
---@field drop?      fun(root: string)             Forget every runtime record for a root

---@type LvimLangState
local M = {
    roots = {},
    toolchains = {},
    sessions = {},
    devices = {},
    selected = {},
    devtools = {},
}

--- Forget every runtime record for a root (session stop / project close). Does not touch
--- config. Callers that own a live session must stop it BEFORE dropping the record.
---@param root string
---@return nil
function M.drop(root)
    M.roots[root] = nil
    M.toolchains[root] = nil
    M.sessions[root] = nil
    M.devices[root] = nil
    M.selected[root] = nil
end

return M
