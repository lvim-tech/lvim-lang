-- lvim-lang.health: :checkhealth lvim-lang.
-- Reports the core picture (enabled, ecosystem dependencies present) and then delegates to
-- each registered provider's own health() for its language-specific checks (SDK found, server
-- available, …). Read-only — it never mutates config or state.
--
---@module "lvim-lang.health"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")

local M = {}

-- Ecosystem plugins lvim-lang bridges into; a missing one degrades specific features.
---@type table<string, string>
local DEPS = {
    ["lvim-lsp"] = "LSP registration + outline bridge",
    ["lvim-tasks"] = "process running (build / dependency commands)",
    ["lvim-ui"] = "pickers / panels",
    ["lvim-utils"] = "config merge / theming / store",
    ["lvim-dap"] = "debugging",
    ["lvim-pkg"] = "toolchain / SDK installation",
}

--- Run the health check.
---@return nil
function M.check()
    local health = vim.health
    health.start("lvim-lang")

    if config.enabled then
        health.ok("Enabled")
    else
        health.warn("Disabled (config.enabled = false) — no provider activates")
    end

    for name, purpose in pairs(DEPS) do
        if pcall(require, name) then
            health.ok(("%s available (%s)"):format(name, purpose))
        else
            health.warn(("%s not found — %s unavailable"):format(name, purpose))
        end
    end

    local names = registry.names()
    if #names == 0 then
        health.info("No providers registered")
    else
        table.sort(names)
        health.info("Providers: " .. table.concat(names, ", "))
    end

    for _, name in ipairs(names) do
        local provider = registry.get(name)
        if provider and provider.health then
            health.start("lvim-lang: " .. name)
            provider.health(health)
        end
    end
end

return M
