-- lvim-lang.servers._declarative: the generic, parameterised lvim-ls server-config module.
-- Providers assembled through the factory (core.declarative) have no hand-written servers/<key>.lua;
-- instead core.declarative.install_server_shims installs a package.preload entry per server key that
-- routes `require("lvim-lang.servers.<key>")` here. build(key) produces the server-config table
-- (cmd / settings / init_options / efm / on_attach) from the owning provider's live catalog. A real
-- servers/<key>.lua on disk always wins over this shim (a bespoke override), so a Tier 1 server that
-- needs custom per-root logic keeps its own module.
--
---@module "lvim-lang.servers._declarative"

local M = {}

--- The lvim-ls server-config table for `key`, built generically from its owning provider's catalog.
---@param key string
---@return table
function M.build(key)
    return require("lvim-lang.core.declarative").server_module(key)
end

return M
