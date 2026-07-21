-- lvim-lang.providers.dart.labels: the Dart closing-labels decoration spec.
-- dartls sends `dart/textDocument/publishClosingLabels` with the full set of widget closing
-- labels for a file; each is placed as faint end-of-line virtual text on the range's LAST line
-- (e.g. `// MyWidget` after a deeply-nested widget's closing paren). Rendering + caching + toggle
-- are the generic core.decorations engine's job — this module only describes the notification.
--
---@module "lvim-lang.providers.dart.labels"

local config = require("lvim-lang.config")

--- The Dart provider's config block.
---@return table
local function opts()
    return config.providers.dart or {}
end

--- Whether closing labels are on: the global decorations switch AND the dart-specific one.
---@return boolean
local function enabled()
    if config.decorations and config.decorations.enabled == false then
        return false
    end
    local deco = opts().decorations or {}
    return deco.closing_labels ~= false
end

--- The prefix prepended to each closing label (a plain code annotation; default "// ").
---@return string
local function prefix()
    local deco = opts().decorations or {}
    return deco.closing_labels_prefix or "// "
end

---@type LvimLangDecorationSpec
return {
    id = "closing_labels",
    method = "dart/textDocument/publishClosingLabels",
    enabled = enabled,

    --- dartls params: { uri, labels = { { label, range = { start, end } }, … } }.
    ---@param params table
    ---@return { uri: string, marks: LvimLangMark[] }
    normalize = function(params)
        local marks = {}
        local pre = prefix()
        for _, l in ipairs(params.labels or {}) do
            local range = l.range or {}
            local last = range["end"] or range.start or { line = 0 }
            marks[#marks + 1] = { lnum = last.line or 0, text = pre .. tostring(l.label) }
        end
        return { uri = params.uri, marks = marks }
    end,
}
