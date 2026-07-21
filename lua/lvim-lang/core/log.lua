-- lvim-lang.core.log: the shared dev-log panel (a persistent output split per project root).
-- A provider's structured runner/daemon streams non-protocol output here; the ring buffer,
-- filtering, error-notify seam and rendering are identical across languages, so a Flutter app
-- log and (later) a cargo run log look and behave the same. This is a scrolling OUTPUT pane
-- (like a quickfix / task terminal), opened with config.dev_log.open_cmd — not a chooser, so it
-- is a real split rather than an lvim-ui modal. Rows are tinted from lvim-lang.highlights.
--
---@module "lvim-lang.core.log"

local config = require("lvim-lang.config")

local M = {}

local FT = "lvimlangdevlog"
local NS = vim.api.nvim_create_namespace("lvim_lang_devlog")

-- Per root: the ring buffer of { text, kind } plus the (reused) scratch buffer handle.
---@type table<string, { lines: { text: string, kind: string }[], bufnr: integer|nil }>
local logs = {}

--- The dev-log store for a root (created on demand).
---@param root string
---@return { lines: { text: string, kind: string }[], bufnr: integer|nil }
local function store(root)
    logs[root] = logs[root] or { lines = {}, bufnr = nil }
    return logs[root]
end

--- The highlight group for a line kind.
---@param kind string
---@return string
local function hl_for(kind)
    if kind == "error" then
        return "LvimLangLogError"
    elseif kind == "info" then
        return "LvimLangLogInfo"
    end
    return "LvimLangLogNormal"
end

--- The window currently displaying `bufnr`, or nil.
---@param bufnr integer|nil
---@return integer|nil
local function win_for(bufnr)
    if not bufnr then
        return nil
    end
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == bufnr then
            return win
        end
    end
    return nil
end

--- Scroll a buffer's window (if visible) to the last line.
---@param bufnr integer
local function autoscroll(bufnr)
    local win = win_for(bufnr)
    if win then
        local n = vim.api.nvim_buf_line_count(bufnr)
        pcall(vim.api.nvim_win_set_cursor, win, { n, 0 })
    end
end

--- Paint one line (index `idx`, 0-based) with its kind's highlight.
---@param bufnr integer
---@param idx integer
---@param kind string
local function paint(bufnr, idx, kind)
    pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, idx, 0, { line_hl_group = hl_for(kind), end_row = idx })
end

--- Ensure the scratch buffer for a root exists and is filled from the ring.
---@param root string
---@return integer bufnr
local function ensure_buf(root)
    local s = store(root)
    if s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr) then
        return s.bufnr
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = FT
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].modifiable = false
    pcall(vim.api.nvim_buf_set_name, buf, "lvim-lang://dev-log/" .. vim.fs.basename(root))
    s.bufnr = buf
    -- Fill from the ring.
    local texts = {}
    for i, entry in ipairs(s.lines) do
        texts[i] = entry.text
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, texts)
    vim.bo[buf].modifiable = false
    for i, entry in ipairs(s.lines) do
        paint(buf, i - 1, entry.kind)
    end
    return buf
end

--- Append a line to a root's dev log (and, if its panel is open, the buffer + autoscroll).
---@param root string
---@param line string
---@param kind? "normal"|"error"|"info"
---@return nil
function M.append(root, line, kind)
    kind = kind or "normal"
    local cfg = config.dev_log or {}
    if type(cfg.filter) == "function" and cfg.filter(line) == false then
        return
    end
    local s = store(root)
    s.lines[#s.lines + 1] = { text = line, kind = kind }
    local max = cfg.max_lines or 5000
    local trimmed = false
    while #s.lines > max do
        table.remove(s.lines, 1)
        trimmed = true
    end
    if kind == "error" and cfg.notify_errors then
        vim.notify(line, vim.log.levels.ERROR, { title = "lvim-lang" })
    end
    local buf = s.bufnr
    if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.bo[buf].modifiable = true
        if trimmed then
            -- Ring rotated: repaint the whole (bounded) buffer to keep line ↔ kind aligned.
            vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
            local texts = {}
            for i, e in ipairs(s.lines) do
                texts[i] = e.text
            end
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, texts)
            for i, e in ipairs(s.lines) do
                paint(buf, i - 1, e.kind)
            end
        else
            local idx = vim.api.nvim_buf_line_count(buf)
            -- A fresh empty buffer reports 1 line; replace that blank first line.
            if idx == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "" and #s.lines == 1 then
                idx = 0
                vim.api.nvim_buf_set_lines(buf, 0, 1, false, { line })
            else
                vim.api.nvim_buf_set_lines(buf, idx, idx, false, { line })
            end
            paint(buf, idx, kind)
        end
        vim.bo[buf].modifiable = false
        autoscroll(buf)
    end
end

--- Clear a root's dev-log buffer and ring.
---@param root string
---@return nil
function M.clear(root)
    local s = store(root)
    s.lines = {}
    if s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr) then
        vim.bo[s.bufnr].modifiable = true
        vim.api.nvim_buf_clear_namespace(s.bufnr, NS, 0, -1)
        vim.api.nvim_buf_set_lines(s.bufnr, 0, -1, false, {})
        vim.bo[s.bufnr].modifiable = false
    end
end

--- Ensure the dev-log panel for a root is visible (idempotent; opens it if not already shown).
---@param root string
---@param layout? string
---@return nil
function M.open(root, layout)
    if not win_for(store(root).bufnr) then
        M.toggle(root, layout)
    end
end

--- Toggle the dev-log panel for a root (opens with config.dev_log.open_cmd, or `layout`).
---@param root string
---@param layout? string
---@return nil
function M.toggle(root, layout)
    local s = store(root)
    local win = win_for(s.bufnr)
    if win then
        vim.api.nvim_win_close(win, true)
        return
    end
    local buf = ensure_buf(root)
    vim.cmd(layout or (config.dev_log and config.dev_log.open_cmd) or "botright 15split")
    vim.api.nvim_win_set_buf(0, buf)
    autoscroll(buf)
    if not (config.dev_log and config.dev_log.focus_on_open) then
        vim.cmd("wincmd p")
    end
end

return M
