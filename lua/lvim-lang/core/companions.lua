-- lvim-lang.core.companions: secondary ("companion") LSP servers that co-attach across the
-- filetypes of MANY providers — emmet (abbreviations), tailwindcss (utility classes), stylelint
-- (a linter-as-LSP), angular (a framework server). None of these belong to a single language:
-- emmet lives in html + css + jsx + vue + svelte + astro; angular in typescript + html of an Angular
-- project. They are therefore NOT provider data and never touch the per-language factory
-- (core.declarative) — that would couple a cross-cutting concern to one language's record.
--
-- Instead each companion is fanned to the SAME additive lvim-ls seam the providers use
-- (lvim-lsp.register_language: one languages entry per server, filetype-keyed, several clients per
-- buffer), and installs a package.preload server-config shim exactly like a declarative provider —
-- so no servers/<key>.lua is owed. The FILETYPE list is the companion's own (spanning providers),
-- and the ROOT GATE is the documented "server config() returns nil ⇒ do not start" contract: a
-- companion with require_root = true resolves its markers and returns nil where the project marker
-- is absent, so tailwind/angular never spawn a client in a plain CSS/TS buffer.
--
-- Fully user-configurable through config.companions[<key>] (enabled / mason / cmd / filetypes /
-- root_required / root_patterns / settings / init_options); a "${root}" token in cmd is substituted
-- with the resolved project root per attach (ngserver's probe locations). Disabling one is
-- config.companions[<key>].enabled = false (or dropping the key).
--
---@module "lvim-lang.core.companions"

local config = require("lvim-lang.config")

-- Companion server-config shims live under the SAME prefix as provider servers (servers/<key>.lua),
-- so lvim-ls' register_language(key, entry, DIR_PREFIX) finds them; a real on-disk module wins.
local DIR_PREFIX = "lvim-lang.servers"

local M = {}

--- The LSP client_capabilities fragment: lvim-cmp's when present, else the Neovim defaults.
---@return table
local function capabilities()
    local ok, cmp = pcall(require, "lvim-cmp")
    if ok and type(cmp.capabilities) == "function" then
        return cmp.capabilities()
    end
    return vim.lsp.protocol.make_client_capabilities()
end

--- Resolve the project root for a companion from the current buffer, using its markers. Returns nil
--- when no marker is found (so a require_root companion can gate on it), else the marker root or the
--- buffer's own directory / cwd as a fallback for the non-gated companions.
---@param patterns string[]
---@return string|nil found, string root
local function resolve_root(patterns)
    local buf = vim.api.nvim_get_current_buf()
    local found = vim.fs.root(buf, patterns)
    if found then
        return found, found
    end
    local nm = vim.api.nvim_buf_get_name(buf)
    local fallback = nm ~= "" and vim.fs.dirname(nm) or (vim.uv.cwd() or ".")
    return nil, fallback
end

--- The lvim-ls server-config table for one companion `key`, built from its config.companions entry.
--- The `config()` function is the root gate: when the companion requires a project marker and none is
--- found, it returns nil and lvim-ls skips starting the server for that buffer/root (manager contract).
---@param key string
---@return table
function M.server_module(key)
    local entry = (config.companions or {})[key] or {}
    local patterns = entry.root_patterns or { ".git" }
    return {
        lsp = {
            root_patterns = patterns,
            --- Built fresh per root so ${root} tokens (ngserver probe paths) track the project.
            ---@return table|nil
            config = function()
                local found, root = resolve_root(patterns)
                -- Root gate: a project-scoped companion (tailwind / angular) does not start where its
                -- marker is absent — the documented "config() returns nil ⇒ no client" seam, not a hack.
                if entry.require_root and not found then
                    return nil
                end
                local cmd = {}
                for _, arg in ipairs(entry.cmd or { entry.mason or key }) do
                    cmd[#cmd + 1] = arg == "${root}" and root or arg
                end
                local cfg = {
                    cmd = cmd, -- cmd[1] is resolved against PATH / lvim-pkg / mason by lvim-ls
                    filetypes = entry.filetypes,
                    capabilities = capabilities(),
                }
                -- Empty settings/init_options encode as a JSON array ([]) which servers reject; omit them.
                if entry.settings and next(entry.settings) then
                    cfg.settings = vim.deepcopy(entry.settings)
                end
                if entry.init_options and next(entry.init_options) then
                    cfg.init_options = vim.deepcopy(entry.init_options)
                end
                return cfg
            end,
        },
    }
end

--- Install a package.preload server-config shim per companion key (so require("lvim-lang.servers.<key>")
--- routes here). A real servers/<key>.lua on disk always wins (the on-disk check via nvim_get_runtime_file,
--- not package.searchpath — which cannot see Neovim rtp lua modules and would shadow a bespoke override).
---@return nil
local function install_shims()
    for key in pairs(config.companions or {}) do
        local mod = DIR_PREFIX .. "." .. key
        local rel = "lua/" .. mod:gsub("%.", "/") .. ".lua"
        local on_disk = #vim.api.nvim_get_runtime_file(rel, false) > 0
        if not on_disk and package.loaded[mod] == nil and package.preload[mod] == nil then
            package.preload[mod] = function()
                return M.server_module(key)
            end
        end
    end
end

--- Register every enabled companion with lvim-ls (additive; starts nothing itself — the manager
--- attaches per buffer / root). Honours config.disable exactly like the providers, so a name listed
--- there is skipped (leaving it free for a user override). No-ops when lvim-ls is unavailable.
---@param disabled? table<string, boolean>  companion keys to skip (from config.disable)
---@return nil
function M.setup(disabled)
    disabled = disabled or {}
    install_shims()
    local ok, lsp = pcall(require, "lvim-lsp")
    if not ok or type(lsp.register_language) ~= "function" then
        return
    end
    for key, entry in pairs(config.companions or {}) do
        if entry.enabled ~= false and not disabled[key] then
            -- One lvim-ls languages entry: filetype-keyed, carrying the companion's own mason install
            -- so lvim-installer offers exactly this server. cmd/settings come from the shim's config().
            local item = entry.mason and (entry.bin and { entry.mason, bin = entry.bin } or entry.mason) or nil
            lsp.register_language(key, { filetypes = entry.filetypes, lsp = item and { item } or {} }, DIR_PREFIX)
        end
    end
end

return M
