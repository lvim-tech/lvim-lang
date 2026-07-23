-- lvim-lang.core.requirements: surface a provider's tool / runtime REQUIREMENTS with resolution hints.
-- A tool a provider activates can be INSTALLED yet UNUSABLE — a JVM too old for jdtls, a missing project
-- eslint, no dotnet SDK, an absent treesitter parser. Rather than let the language server die with an
-- opaque `exit code 1`, a provider declares an optional `requirements(root)` returning a list of checks;
-- the core surfaces the FAILING ones with a concrete `hint` on how to fix each — proactively, ONCE, as a
-- notice when the provider first activates for a root, AND in `:checkhealth lvim-lang`. Every provider
-- shares this one mechanism, so the surfacing is uniform. Detection only — nothing is installed here.
--
---@module "lvim-lang.core.requirements"

---@class LvimLangRequirement
---@field label     string    what is being checked (e.g. "jdtls Java runtime")
---@field ok        boolean   is it satisfied?
---@field detail?   string    the observed state (e.g. "found Java 17")
---@field hint?     string    how to resolve it when not ok
---@field severity? "error"|"warn"|"info"  default "warn" (for the notice level + health line)

local M = {}

---@type table<string, boolean>  (root .. "\0" .. label) already notified this session
local notified = {}

--- The requirement list a provider declares for `root` (empty when it declares none / errors).
---@param name string
---@param root string
---@return LvimLangRequirement[]
function M.check(name, root)
    local spec = require("lvim-lang.registry").get(name)
    if not spec or type(spec.requirements) ~= "function" then
        return {}
    end
    local ok, list = pcall(spec.requirements, root)
    return (ok and type(list) == "table") and list or {}
end

--- A ready-made requirement: "the toolchain tool `key` resolves for `root`". Most providers need only
--- this — their language server is installed on demand, but the underlying RUNTIME (node, dotnet, the
--- Go / Rust / Dart / Python toolchain) is the user's own and, when absent, makes the server crash with
--- no useful message. Present → ok; absent → a warning carrying `hint` (how to install it).
---@param provider string  the provider name (also the toolchain namespace)
---@param key string       the toolchain tool key (e.g. "node", "dotnet", "go")
---@param label string     human label for the runtime
---@param hint string      how to resolve it when missing
---@param root string
---@return LvimLangRequirement
function M.tool_present(provider, key, label, hint, root)
    local bin = require("lvim-lang.core.toolchain").resolve(provider, key, root)
    return {
        label = label,
        ok = bin ~= nil,
        detail = bin and ("found: " .. bin) or "not found",
        hint = hint,
        severity = "warn",
    }
end

--- Notify each FAILING requirement once (per root + label), so the user learns the problem + the fix at
--- activation instead of from a silent server crash. A no-op when everything is satisfied. `info`-level
--- requirements (advisory tips, e.g. "no compile DB") are NOT popped as notices — they surface only in
--- `:checkhealth` — so activation stays quiet unless something actually needs the user's action.
---@param name string
---@param root string
---@return nil
function M.notify_failures(name, root)
    for _, r in ipairs(M.check(name, root)) do
        if not r.ok and r.severity ~= "info" then
            local key = root .. "\0" .. (r.label or "")
            if not notified[key] then
                notified[key] = true
                local msg = ("lvim-lang [%s]: %s"):format(name, r.label or "requirement")
                if r.detail then
                    msg = msg .. " — " .. r.detail
                end
                if r.hint then
                    msg = msg .. "\n→ " .. r.hint
                end
                local lvl = (r.severity == "error" and vim.log.levels.ERROR)
                    or (r.severity == "info" and vim.log.levels.INFO)
                    or vim.log.levels.WARN
                vim.notify(msg, lvl, { title = "lvim-lang" })
            end
        end
    end
end

--- Report a provider's requirements to a `:checkhealth` reporter (ok → ok, else warn/info with the hint).
---@param name string
---@param root string
---@param h table  the vim.health reporter
---@return nil
function M.health(name, root, h)
    for _, r in ipairs(M.check(name, root)) do
        local line = (r.label or "requirement") .. (r.detail and (" — " .. r.detail) or "")
        if r.ok then
            h.ok(line)
        else
            local resolved = line .. (r.hint and ("  → " .. r.hint) or "")
            if r.severity == "info" then
                h.info(resolved)
            else
                h.warn(resolved)
            end
        end
    end
end

return M
