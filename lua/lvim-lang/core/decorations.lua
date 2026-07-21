-- lvim-lang.core.decorations: a generic "LSP notification → extmark / virtual text" engine.
-- One mechanism serves every language's decoration notifications (Dart closing labels, and later
-- JSX close tags, metals decorations): a provider registers a spec { id, method, enabled,
-- normalize } and the server config wires decorations.handler(spec) as the LSP handler for
-- `method`. The handler normalizes the payload to a per-buffer set of marks, caches it (so a live
-- toggle repaints WITHOUT a new notification), and paints it in the spec's own namespace — a full
-- replace per notification, since the server sends the complete set each time. Highlight groups
-- come from lvim-lang.highlights (self-themed), never hard-coded.
--
---@module "lvim-lang.core.decorations"

---@class LvimLangMark
---@field lnum integer   0-based line the virtual text attaches to (end-of-line)
---@field text string    Already-formatted virtual text (plain — a code annotation, not a glyph)
---@field hl?  string    Highlight group override (default LvimLangDecoration)

---@class LvimLangDecorationSpec
---@field id        string                                   Stable id, e.g. "closing_labels"
---@field method    string                                   LSP notification method
---@field enabled   fun(): boolean                           Initial on/off, read from live config
---@field normalize fun(params: table): { uri: string, marks: LvimLangMark[] }

local M = {}

---@type table<string, LvimLangDecorationSpec>  id → spec
local specs = {}
---@type table<string, boolean>                 id → runtime on/off (seeded from spec.enabled())
local enabled = {}
---@type table<integer, table<string, LvimLangMark[]>>  bufnr → id → marks (repaint cache)
local cache = {}
---@type table<string, integer>                 id → extmark namespace
local namespaces = {}

--- The extmark namespace for a decoration id (created on first use).
---@param id string
---@return integer
local function ns_for(id)
    if not namespaces[id] then
        namespaces[id] = vim.api.nvim_create_namespace("lvim_lang_deco_" .. id)
    end
    return namespaces[id]
end

--- One-time autocmd: drop a buffer's cached marks when it is wiped.
local cleanup_armed = false
local function arm_cleanup()
    if cleanup_armed then
        return
    end
    cleanup_armed = true
    vim.api.nvim_create_autocmd("BufWipeout", {
        group = vim.api.nvim_create_augroup("lvim_lang_decorations", { clear = true }),
        callback = function(args)
            cache[args.buf] = nil
        end,
        desc = "lvim-lang: drop cached decoration marks for a wiped buffer",
    })
end

--- Repaint one decoration id in a buffer from its cache (clears first; no-op paint when off).
---@param bufnr integer
---@param id string
---@return nil
local function render(bufnr, id)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    local ns = ns_for(id)
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    if not enabled[id] then
        return
    end
    for _, mark in ipairs((cache[bufnr] or {})[id] or {}) do
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, mark.lnum, 0, {
            virt_text = { { mark.text, mark.hl or "LvimLangDecoration" } },
            virt_text_pos = "eol",
            hl_mode = "combine",
        })
    end
end

--- Register a decoration spec (seeds its on/off state from config). Called once per spec at
--- provider registration, so a toggle works even before the first notification arrives.
---@param spec LvimLangDecorationSpec
---@return nil
function M.register(spec)
    specs[spec.id] = spec
    if enabled[spec.id] == nil then
        enabled[spec.id] = spec.enabled() ~= false
    end
    arm_cleanup()
end

--- Build the LSP notification handler for a decoration spec (wired into the server config's
--- `handlers` for spec.method). Caches the normalized marks per buffer and repaints.
---@param spec LvimLangDecorationSpec
---@return fun(err: any, result: table, ctx: table)
function M.handler(spec)
    M.register(spec)
    return function(err, result, _ctx)
        if err or type(result) ~= "table" or not result.uri then
            return
        end
        local bufnr = vim.uri_to_bufnr(result.uri)
        if not vim.api.nvim_buf_is_valid(bufnr) then
            return
        end
        local norm = spec.normalize(result)
        cache[bufnr] = cache[bufnr] or {}
        cache[bufnr][spec.id] = norm.marks
        render(bufnr, spec.id)
    end
end

--- Set a decoration id on/off and repaint every buffer that has cached marks for it.
---@param id string
---@param on boolean
---@return nil
function M.set_enabled(id, on)
    enabled[id] = on
    for bufnr, by_id in pairs(cache) do
        if by_id[id] then
            render(bufnr, id)
        end
    end
end

--- Toggle a decoration id; returns the new state.
---@param id string
---@return boolean
function M.toggle(id)
    M.set_enabled(id, not enabled[id])
    return enabled[id]
end

--- Whether a decoration id is currently on.
---@param id string
---@return boolean
function M.is_enabled(id)
    return enabled[id] == true
end

return M
