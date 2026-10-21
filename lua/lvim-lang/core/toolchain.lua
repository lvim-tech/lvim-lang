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
    local kinds = winner_kind[root] or {}
    for k in pairs(cached) do
        if vim.startswith(k, prefix) then
            cached[k] = nil
            -- The kind record is read only beside a live path, but the two caches must not drift:
            -- what is forgotten is forgotten in both.
            kinds[k] = nil
        end
    end
end

--- The same directory, through whichever symlinks name it? A version manager's `latest` is
--- usually a link to the versioned directory beside it, and re-pointing GOROOT from one spelling
--- of an install to another spelling of the SAME install is churn, not a fix.
---@param a string
---@param b string
---@return boolean
local function same_dir(a, b)
    if a == b then
        return true
    end
    local ra, rb = vim.uv.fs_realpath(a), vim.uv.fs_realpath(b)
    return ra ~= nil and ra == rb
end

--- Would a child's PATH lookup of `path`'s own binary NAME land on `path` itself?
--- Presence of the directory on PATH is NOT the question: when an EARLIER entry holds a binary of the
--- same name, the child finds THAT one — a second install of the very tool the editor resolved, which
--- is the mix-up env() exists to prevent. Only the first entry that holds the name can win, so the
--- walk stops there.
---@param path_value string
---@param path string                 the resolved absolute path of the tool
---@param sep string
---@return boolean
local function path_resolves(path_value, path, sep)
    local bin = vim.fs.basename(path)
    local dir = vim.fs.normalize(vim.fs.dirname(path))
    for _, entry in ipairs(vim.split(path_value, sep, { plain = true })) do
        if entry ~= "" then
            local e = vim.fs.normalize(entry)
            if vim.fn.executable(e .. "/" .. bin) == 1 then
                return same_dir(e, dir)
            end
        end
    end
    return false
end

--- The environment a process spawned from a resolved toolchain binary needs, merged under `base`.
--- A tool resolved to an absolute path inside a version-manager / SDK install (`rustup which`,
--- `mise which`, FVM, an explicit pin) is NOT what the inherited PATH points at: run directly, its
--- own child lookups (rust-analyzer → rustc / the proc-macro server, cargo → rustc, gopls → go, a
--- node script → node, jdtls → JAVA_HOME) would hit a DIFFERENT install through PATH. A proxy (rustup,
--- mise shims) would have set the env up; a direct spawn must do it here.
--- The bin dir of the provider's RUNTIMES — when won by a "path" strategy and when PATH would
--- otherwise resolve that binary's name to ANOTHER directory — goes first on PATH, the one about to
--- run ahead of the rest. A runtime's `home` var (GOROOT / JAVA_HOME) is re-pointed at the resolved
--- install whenever the editor's env names a different one, INDEPENDENTLY of PATH: a right PATH with
--- a stale GOROOT still compiles against another standard library. Returns `base` unchanged
--- (possibly nil) when nothing needs to change.
---@param provider string
---@param root string
---@param tool? string                  the binary about to be spawned; when it is one of the provider's
---                                     runtimes, that install leads PATH (and is resolved for it)
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
        -- The install root, which a `home` var points AT (its bin dir is one level down). Decided
        -- before PATH and regardless of it: the two are independent facts about the same install.
        if home then
            local current = vim.env[home]
            local install = vim.fs.dirname(dir)
            if current and current ~= "" and not same_dir(vim.fs.normalize(current), install) then
                homes[home] = homes[home] or install
            end
        end
        if path_resolves(path_value, path, sep) or seen[dir] then
            return
        end
        seen[dir] = true
        dirs[#dirs + 1] = dir
    end
    -- Only a RUNTIME / SDK directory is worth putting first, so the runtimes are the whole list.
    -- A package-managed server (lvim-pkg, mason) lives in a SHARED bin dir of unrelated tools —
    -- prettier, dlv, golangci-lint, efm — which holds no runtime for it to find; leading PATH with
    -- it would shadow the project's own tools (node_modules/.bin) for everything that server shells
    -- out to. `tool` therefore only says which runtime is about to RUN: its install goes first, and
    -- is resolved even when it is an optional one.
    local order = {}
    for i, rt in ipairs(spec.toolchain.runtimes or {}) do
        -- Eager for the primary runtime, one declared required, and the one about to run; an
        -- optional runtime is otherwise used only once something else has cached it.
        local entry = { rt = rt, eager = i == 1 or rt.require == true or rt.key == tool }
        if rt.key == tool then
            table.insert(order, 1, entry)
        else
            order[#order + 1] = entry
        end
    end
    for _, entry in ipairs(order) do
        consider(entry.rt.key, entry.eager, entry.rt.home)
    end
    if #dirs == 0 and next(homes) == nil then
        return base
    end
    local env = {}
    if #dirs > 0 then
        env.PATH = table.concat(dirs, sep) .. (path_value ~= "" and (sep .. path_value) or "")
    end
    for var, dir in pairs(homes) do
        env[var] = dir
    end
    return vim.tbl_extend("force", env, base or {})
end

return M
