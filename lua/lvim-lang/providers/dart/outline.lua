-- lvim-lang.providers.dart.outline: the Flutter Outline source for the lvim-lsp outline panel.
-- dartls pushes `dart/textDocument/publishFlutterOutline` with the full widget/element tree of a
-- file — richer than textDocument/documentSymbol because it includes the nested WIDGET instances,
-- not just declarations. This module normalizes that tree into the lvim-lsp outline node shape and
-- pushes it into the existing outline panel as an alternative SOURCE (no second panel). The handler
-- caches the latest tree per buffer so attaching the panel renders immediately.
--
---@module "lvim-lang.providers.dart.outline"

local M = {}

local SK = vim.lsp.protocol.SymbolKind

-- Map a dartElement kind to an LSP SymbolKind (for the panel's icon); widget instances with no
-- dartElement fall back to Object.
local DART_KIND = {
    CLASS = SK.Class,
    MIXIN = SK.Class,
    ENUM = SK.Enum,
    ENUM_CONSTANT = SK.EnumMember,
    EXTENSION = SK.Class,
    CONSTRUCTOR = SK.Constructor,
    METHOD = SK.Method,
    FUNCTION = SK.Function,
    GETTER = SK.Property,
    SETTER = SK.Property,
    FIELD = SK.Field,
    TOP_LEVEL_VARIABLE = SK.Variable,
}

---@type table<integer, table[]>  bufnr → latest normalized nodes
local cache = {}
---@type table<integer, fun(nodes: table[])>  bufnr → the panel's push callback (while attached)
local pushers = {}

--- The display name for a Flutter outline node.
---@param node table
---@return string
local function node_name(node)
    local de = node.dartElement
    if de and type(de.name) == "string" and de.name ~= "" then
        return de.name
    end
    return node.className or node.label or node.kind or "widget"
end

--- The LSP SymbolKind for a node.
---@param node table
---@return integer
local function node_kind(node)
    local de = node.dartElement
    if de and de.kind and DART_KIND[de.kind] then
        return DART_KIND[de.kind]
    end
    return SK.Object
end

--- Normalize a Flutter outline node (and its children) to the lvim-lsp outline node shape.
---@param node table
---@return table
local function normalize(node)
    local raw = node.codeRange or node.range or {}
    local start = raw.start or { line = 0, character = 0 }
    -- Always hand the panel a complete range (start + end); a Flutter outline node can lack
    -- codeRange, and the panel's follow/auto-fold read range.start.
    local range = { start = start, ["end"] = raw["end"] or start }
    local children = {}
    for _, child in ipairs(node.children or {}) do
        children[#children + 1] = normalize(child)
    end
    return {
        name = node_name(node),
        kind = node_kind(node),
        lnum = (start.line or 0) + 1,
        col = (start.character or 0) + 1,
        range = range,
        children = children,
    }
end

--- Arm the one-time cleanup that drops caches/pushers for wiped buffers.
local cleanup_armed = false
local function arm_cleanup()
    if cleanup_armed then
        return
    end
    cleanup_armed = true
    vim.api.nvim_create_autocmd("BufWipeout", {
        group = vim.api.nvim_create_augroup("lvim_lang_dart_outline", { clear = true }),
        callback = function(args)
            cache[args.buf] = nil
            pushers[args.buf] = nil
        end,
    })
end

--- The LSP notification handler for publishFlutterOutline (wired in servers/dart.lua).
---@return fun(err: any, result: table, ctx: table)
function M.handler()
    arm_cleanup()
    return function(err, result, _ctx)
        if err or type(result) ~= "table" or not result.uri or type(result.outline) ~= "table" then
            return
        end
        local bufnr = vim.uri_to_bufnr(result.uri)
        if not vim.api.nvim_buf_is_valid(bufnr) then
            return
        end
        -- The root outline node represents the whole file; its children are the top-level
        -- declarations / widgets we show.
        local nodes = {}
        for _, child in ipairs(result.outline.children or {}) do
            nodes[#nodes + 1] = normalize(child)
        end
        cache[bufnr] = nodes
        if pushers[bufnr] then
            pushers[bufnr](nodes)
        end
    end
end

-- The outline source handed to the lvim-lsp panel via core.outline.
---@type LvimLangOutlineSpec
M.spec = {
    filetypes = { "dart" },
    source = {
        attach = function(bufnr, push)
            pushers[bufnr] = push
            if cache[bufnr] then
                push(cache[bufnr])
            end
        end,
        detach = function(bufnr)
            pushers[bufnr] = nil
        end,
    },
}

return M
