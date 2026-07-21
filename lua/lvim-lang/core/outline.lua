-- lvim-lang.core.outline: bridge an alternative outline SOURCE into the existing lvim-lsp panel.
-- Some servers expose a richer tree than textDocument/documentSymbol (dartls' Flutter Outline,
-- metals' tree view). Rather than open a second panel, a provider declares a source that pushes
-- normalized nodes (the lvim-lsp outline node shape) and this module hands it to lvim-lsp'
-- outline register_source seam — the ONE canonical outline panel then renders the widget tree.
--
-- Implemented in milestone M7 (needs the register_source seam added to lvim-lsp). Stub documents it.
--
---@module "lvim-lang.core.outline"

---@class LvimLangOutlineSpec
---@field filetypes string[]
---@field source    { attach: fun(bufnr: integer, push: fun(nodes: table[])), detach: fun(bufnr: integer) }

local M = {}

--- Register a provider outline source with the lvim-lsp outline panel.
---@param spec LvimLangOutlineSpec
---@return nil
function M.register(spec)
    local ok, lsp = pcall(require, "lvim-lsp")
    if not ok or type(lsp.outline_register_source) ~= "function" then
        return -- M7 adds outline_register_source to lvim-lsp
    end
    for _, ft in ipairs(spec.filetypes or {}) do
        lsp.outline_register_source(ft, spec.source)
    end
end

return M
