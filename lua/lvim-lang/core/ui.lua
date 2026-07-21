-- lvim-lang.core.ui: shared UI helpers, all routed through the canonical lvim-ui primitives.
-- lvim-lang never opens a raw float or calls vim.ui.select: device / target / command pickers
-- go through lvim-ui.select, the run-flags menu through lvim-ui.transient, the help window
-- follows the outline show_help canon, and statusline getters aggregate provider segments.
--
-- Implemented across M6 (pickers) / M9 (transient, statusline). The stub documents the contract.
--
---@module "lvim-lang.core.ui"

local M = {}

--- Pick one item through the canonical centered picker.
---@param opts { title: string, items: table[], current?: integer }
---@param cb fun(item: table|nil, index: integer|nil)
---@return nil
function M.pick(opts, cb)
    local ok, ui = pcall(require, "lvim-ui")
    if not ok then
        return
    end
    ui.select({
        title = opts.title,
        items = opts.items,
        current_item = opts.current,
        callback = function(confirmed, index)
            cb(confirmed and opts.items[index] or nil, confirmed and index or nil)
        end,
    })
end

--- The statusline segment for a buffer: the active provider's segment (empty when none, or when
--- statusline segments are disabled).
---@param bufnr? integer
---@return string
function M.statusline(bufnr)
    local config = require("lvim-lang.config")
    if config.statusline == false then
        return ""
    end
    local provider, root = require("lvim-lang.registry").for_buffer(bufnr)
    if provider and provider.statusline and root then
        local ok, segment = pcall(provider.statusline, root)
        return (ok and type(segment) == "string") and segment or ""
    end
    return ""
end

return M
