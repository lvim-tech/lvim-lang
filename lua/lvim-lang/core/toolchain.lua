-- lvim-lang.core.toolchain: SDK / toolchain resolution (detection only, never installation).
-- A provider declares an ORDERED list of strategies per tool in its toolchain spec; resolve()
-- runs them in order and returns the first candidate that is an executable, caching the winner
-- in lvim-lang.state per (root, provider, tool). Missing tools return nil + a reason for health
-- and the toolchain command. Installation is a separate concern (lvim-pkg); this module only
-- finds what already exists on disk / PATH.
--
---@module "lvim-lang.core.toolchain"

local state = require("lvim-lang.state")

---@class LvimLangToolchainStrategy
---@field kind  "path"|"which"                     "path" verifies a literal/derived path is executable; "which" looks a binary up on PATH
---@field value string|fun(root: string): string|nil  Literal path / binary name, or a resolver of one

---@class LvimLangToolchainSpec
---@field tools    table<string, LvimLangToolchainStrategy[]>  tool name → ordered strategies
---@field version? fun(bin: string): string|nil               Version string builder (for status/health)

local M = {}

--- Compound cache key so several providers can share a root without colliding.
---@param provider string
---@param tool string
---@return string
local function key(provider, tool)
    return provider .. ":" .. tool
end

--- Resolve one strategy to an executable path, or nil.
---@param strategy LvimLangToolchainStrategy
---@param root string
---@return string|nil
local function try(strategy, root)
    local v = strategy.value
    local resolved = type(v) == "function" and v(root) or v
    if type(resolved) ~= "string" or resolved == "" then
        return nil
    end
    if strategy.kind == "which" then
        local path = vim.fn.exepath(resolved)
        return path ~= "" and path or nil
    end
    -- kind == "path": a concrete path is only a winner if it is actually executable
    if vim.fn.executable(resolved) == 1 then
        return resolved
    end
    return nil
end

--- Resolve `tool` for `root` using `provider`'s strategies; caches and returns the winner, or
--- nil + a reason when no strategy yields an executable.
---@param provider string
---@param tool string
---@param root string
---@return string|nil path, string|nil reason
function M.resolve(provider, tool, root)
    local cached = state.toolchains[root]
    if cached and cached[key(provider, tool)] then
        return cached[key(provider, tool)]
    end
    local spec = require("lvim-lang.registry").get(provider)
    if not spec or not spec.toolchain then
        return nil, "no toolchain spec for provider '" .. provider .. "'"
    end
    local strategies = spec.toolchain.tools[tool]
    if not strategies then
        return nil, "no strategy for tool '" .. tool .. "'"
    end
    for _, strategy in ipairs(strategies) do
        local path = try(strategy, root)
        if path then
            state.toolchains[root] = state.toolchains[root] or {}
            state.toolchains[root][key(provider, tool)] = path
            return path
        end
    end
    return nil, tool .. " not found (checked " .. #strategies .. " location(s))"
end

--- The version string for a resolved tool, via the provider's `version` hook (nil when absent
--- or when the tool cannot be resolved).
---@param provider string
---@param tool string
---@param root string
---@return string|nil
function M.version(provider, tool, root)
    local spec = require("lvim-lang.registry").get(provider)
    if not spec or not spec.toolchain or not spec.toolchain.version then
        return nil
    end
    local path = M.resolve(provider, tool, root)
    if not path then
        return nil
    end
    return spec.toolchain.version(path)
end

--- Invalidate the cached resolutions of a provider for a root (e.g. after an FVM version
--- switch), so the next resolve() re-runs the strategies.
---@param provider string
---@param root string
---@return nil
function M.invalidate(provider, root)
    local cached = state.toolchains[root]
    if not cached then
        return
    end
    local prefix = provider .. ":"
    for k in pairs(cached) do
        if vim.startswith(k, prefix) then
            cached[k] = nil
        end
    end
end

return M
