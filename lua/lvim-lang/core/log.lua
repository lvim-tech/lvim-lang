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

-- The split command per horizontal/vertical placement (a %d for the fixed size). "area" docks in
-- the lvim-msgarea zone when available, else falls back to a bottom split.
local SPLIT = {
    bottom = "botright %dsplit",
    top = "topleft %dsplit",
    area = "botright %dsplit",
    right = "botright %dvsplit",
    left = "topleft %dvsplit",
}

--- Resolve the effective placement: a command-token override → the panel's own layout →
--- the global config.layout → "bottom".
---@param override? string
---@return string
local function resolve_layout(override)
    local dl = config.dev_log or {}
    return override or dl.layout or config.layout or "bottom"
end

--- Apply the canonical panel window options (title winbar, fixed size, no gutters, q to close).
---@param win integer
---@param buf integer
---@param horiz boolean
---@return nil
local function dress(win, buf, horiz)
    if horiz then
        vim.wo[win].winfixheight = true
    else
        vim.wo[win].winfixwidth = true
    end
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].winbar = "%#LvimLangLogTitle# 󰔶 Flutter Dev Log %*"
    pcall(function()
        vim.wo[win].winfixbuf = true
    end)
    vim.keymap.set("n", "q", function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, { buffer = buf, nowait = true, silent = true, desc = "close the dev log" })
end

--- Open the dev-log window for a root in `layout` (native split, or a centered float).
---@param root string
---@param layout string
---@return nil
local function open_window(root, layout)
    local buf = ensure_buf(root)
    local dl = config.dev_log or {}
    local prev = vim.api.nvim_get_current_win()
    if layout == "float" then
        local cols, rows = vim.o.columns, vim.o.lines
        local width = math.floor(cols * 0.7)
        local height = math.floor(rows * 0.5)
        local win = vim.api.nvim_open_win(buf, dl.focus_on_open == true, {
            relative = "editor",
            width = width,
            height = height,
            row = math.floor((rows - height) / 2 - 1),
            col = math.floor((cols - width) / 2),
            style = "minimal",
            border = "rounded",
            title = " 󰔶 Flutter Dev Log ",
            title_pos = "center",
        })
        -- Border title only — no winbar (splits inherit winbar; a float must not carry it).
        vim.wo[win].winbar = ""
        vim.keymap.set("n", "q", function()
            if vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_win_close(win, true)
            end
        end, { buffer = buf, nowait = true, silent = true, desc = "close the dev log" })
    else
        local horiz = layout == "bottom" or layout == "top" or layout == "area"
        local size = horiz and (dl.height or 15) or (dl.width or 60)
        vim.cmd((SPLIT[layout] or SPLIT.bottom):format(size))
        local win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(win, buf)
        dress(win, buf, horiz)
    end
    autoscroll(buf)
    if dl.focus_on_open ~= true and vim.api.nvim_win_is_valid(prev) then
        vim.api.nvim_set_current_win(prev)
    end
end

--- Ensure the dev-log panel for a root is visible (idempotent). `layout` overrides the placement.
---@param root string
---@param layout? string
---@return nil
function M.open(root, layout)
    if not win_for(store(root).bufnr) then
        open_window(root, resolve_layout(layout))
    end
end

--- Toggle the dev-log panel for a root (placement: `layout` token → config).
---@param root string
---@param layout? string
---@return nil
function M.toggle(root, layout)
    local win = win_for(store(root).bufnr)
    if win then
        vim.api.nvim_win_close(win, true)
        return
    end
    open_window(root, resolve_layout(layout))
end

return M
