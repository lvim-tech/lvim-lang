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

---@class LvimLangToolchainRuntime
---@field key      string   toolchain key of a user-owned runtime/SDK tool (cargo, go, java, node …)
---@field require? boolean  resolved eagerly by env(); an optional runtime is only used once cached
---@field home?    string   env var naming the install root (GOROOT, JAVA_HOME), re-pointed by env()

---@class LvimLangToolchainSpec
---@field tools     table<string, LvimLangToolchainStrategy[]>  tool name → ordered strategies
---@field runtimes? LvimLangToolchainRuntime[]                 the provider's runtimes, in declared order
---@field version?  fun(bin: string): string|nil               Version string builder (for status/health)

local M = {}

-- root → ("provider:tool" → the winning strategy kind). Kept beside the state cache: a "path" winner
-- may live OUTSIDE the inherited PATH (a rustup toolchain dir, a mise-pinned SDK, an FVM SDK), which
-- env() must then put first on PATH for the spawned process. A missing record reads as "unknown".
local winner_kind = {}

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
            winner_kind[root] = winner_kind[root] or {}
            winner_kind[root][key(provider, tool)] = strategy.kind
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

--- Is `dir` already an entry of `path_value` (a PATH string)?
---@param path_value string
---@param dir string
---@param sep string
---@return boolean
local function on_path(path_value, dir, sep)
    for _, entry in ipairs(vim.split(path_value, sep, { plain = true })) do
        if entry ~= "" and vim.fs.normalize(entry) == dir then
            return true
        end
    end
    return false
end

--- The environment a process spawned from a resolved toolchain binary needs, merged under `base`.
--- A tool resolved to an absolute path inside a version-manager / SDK install (`rustup which`,
--- `mise which`, FVM, an explicit pin) is NOT what the inherited PATH points at: run directly, its
--- own child lookups (rust-analyzer → rustc / the proc-macro server, cargo → rustc, gopls → go, a
--- node script → node, jdtls → JAVA_HOME) would hit a DIFFERENT install through PATH. A proxy (rustup,
--- mise shims) would have set the env up; a direct spawn must do it here. The bin dir of `tool` and of
--- the provider's runtimes — when won by a "path" strategy and not already on PATH — goes first on
--- PATH, and a runtime's `home` var (GOROOT / JAVA_HOME), when the editor's env sets it, is re-pointed
--- at that install. Returns `base` unchanged (possibly nil) when nothing needs to change.
---@param provider string
---@param root string
---@param tool? string                  the binary about to be spawned (its own dir is considered first)
---@param base? table<string, string>   an env the caller already passes (wins over ours)
---@return table<string, string>|nil
function M.env(provider, root, tool, base)
    local spec = require("lvim-lang.registry").get(provider)
    if not spec or not spec.toolchain or type(root) ~= "string" then
        return base
    end
    local sep = vim.fn.has("win32") == 1 and ";" or ":"
    local path_value = vim.env.PATH or ""
    local dirs, seen, homes = {}, {}, {}
    --- Collect the bin dir of tool `t` (resolving it when `eager`, else only when already cached).
    local function consider(t, eager, home)
        local k = key(provider, t)
        local path
        if eager then
            path = M.resolve(provider, t, root)
        else
            path = (state.toolchains[root] or {})[k]
        end
        if not path or (winner_kind[root] or {})[k] ~= "path" then
            return
        end
        local dir = vim.fs.normalize(vim.fs.dirname(path))
        if on_path(path_value, dir, sep) then
            return
        end
        if not seen[dir] then
            seen[dir] = true
            dirs[#dirs + 1] = dir
        end
        if home and vim.env[home] and vim.env[home] ~= "" then
            homes[home] = homes[home] or vim.fs.dirname(dir)
        end
    end
    if tool and spec.toolchain.tools[tool] then
        consider(tool, true)
    end
    for i, rt in ipairs(spec.toolchain.runtimes or {}) do
        consider(rt.key, i == 1 or rt.require == true, rt.home)
    end
    if #dirs == 0 then
        return base
    end
    local env = { PATH = table.concat(dirs, sep) .. (path_value ~= "" and (sep .. path_value) or "") }
    for var, dir in pairs(homes) do
        env[var] = dir
    end
    return vim.tbl_extend("force", env, base or {})
end

return M
