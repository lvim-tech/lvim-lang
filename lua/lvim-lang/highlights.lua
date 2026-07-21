-- lvim-lang.highlights: the plugin's highlight groups, self-themed from the lvim-utils palette.
-- Registered through lvim-utils.highlight.bind, so the groups are (re)built from the LIVE
-- palette on setup AND on every colorscheme / palette change — never hard-coded hex. Two
-- families: LvimLangDecoration* (the notification-driven virtual text: closing labels, etc.)
-- and LvimLangLog* (the dev-log panel rows). Everything is a comment-weight tint so it reads
-- as annotation, not as first-class code.
--
---@module "lvim-lang.highlights"

local highlight = require("lvim-utils.highlight")

local M = {}

--- Build every LvimLang* group from the current palette. Passed to highlight.bind, which
--- calls it once now and again on each palette/colorscheme change.
---@return table<string, table>  group name → nvim_set_hl opts
local function build()
    local ok, colors = pcall(require, "lvim-utils.colors")
    if not ok then
        return {
            LvimLangDecoration = { link = "Comment", default = true },
            LvimLangLogNormal = { link = "NormalFloat", default = true },
            LvimLangLogError = { link = "DiagnosticError", default = true },
            LvimLangLogInfo = { link = "Comment", default = true },
        }
    end
    local c = colors
    local bg = c.bg_dark or c.bg
    return {
        -- inline widget/close-tag annotations — a muted accent, no background
        LvimLangDecoration = { fg = c.comment or c.gray or c.fg },
        -- dev-log panel: body on the float bg, errors tinted red, info muted
        LvimLangLogNormal = { fg = c.fg, bg = bg },
        LvimLangLogError = { fg = c.red, bg = highlight.blend(c.red, bg, 0.1) },
        LvimLangLogInfo = { fg = c.comment or c.gray or c.fg, bg = bg },
    }
end

--- Register the groups with the theming system (idempotent; safe to call from setup()).
---@return nil
function M.setup()
    highlight.bind(build)
end

return M
