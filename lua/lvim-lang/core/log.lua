-- lvim-lang.core.log: the shared dev-log panel (one persistent output pane per project root).
-- A provider's structured runner/daemon streams non-protocol output here; the ring buffer, the
-- filtering, the error-notify seam and the rendering are identical across languages, so a Flutter
-- app log and (later) a cargo run log look and behave the same.
--
-- The RING is the source of truth, not a buffer: the panel is a canonical `lvim-ui.surface` whose
-- provider renders the ring on demand, so the same content can be shown as a native split (bottom /
-- top / left / right) or a centered float without any of them owning the data. That is also why the
-- window layer here is tiny — the surface owns the frame, the title band, the theming, the cursor
-- registration and the close keys.
--
-- Appends are DEBOUNCED into one re-render: a chatty stream (flutter run) would otherwise repaint the
-- panel per line. The debounce timer is per root and is closed with the panel, never merely stopped.
--
---@module "lvim-lang.core.log"

local config = require("lvim-lang.config")
local surface = require("lvim-ui.surface")

local M = {}

local FT = "lvimlangdevlog"

--- Per root: the ring buffer of lines, the live panel handles, and the panel name the streaming
--- provider chose for this root.
---@class LvimLangDevLogStore
---@field lines { text: string, kind: string }[]
---@field title string|nil    panel title for THIS root (nil = the configured default)
---@field icon  string|nil    panel glyph for THIS root (nil = the configured default)
---@field surface table|nil   the open `lvim-ui.surface` handle
---@field pan table|nil       its single panel (carries `buf` / `win` / `refresh`)
---@field timer uv.uv_timer_t|nil  the append debounce

---@type table<string, LvimLangDevLogStore>
local logs = {}

--- The dev-log store for a root (created on demand).
---@param root string
---@return LvimLangDevLogStore
local function store(root)
    logs[root] = logs[root] or { lines = {} }
    return logs[root]
end

--- Name the panel for `root`. The dev log is SHARED across languages, so the provider that streams
--- into a root's panel says what it is called ("Flutter Dev Log"); anything that never sets one falls
--- back to the neutral `dev_log.title` / `dev_log.icon` from config.
---@param root string
---@param title string?
---@param icon string?
---@return nil
function M.set_title(root, title, icon)
    local s = store(root)
    s.title = title
    s.icon = icon
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

--- Is the panel for `root` on screen?
---@param root string
---@return boolean
local function visible(root)
    local s = store(root)
    return s.pan ~= nil and s.pan.win ~= nil and vim.api.nvim_win_is_valid(s.pan.win)
end

--- Scroll the panel to its last line — a log follows its tail.
---@param root string
---@return nil
local function autoscroll(root)
    local s = store(root)
    if not visible(root) then
        return
    end
    local count = vim.api.nvim_buf_line_count(s.pan.buf)
    pcall(vim.api.nvim_win_set_cursor, s.pan.win, { count, 0 })
end

--- Close and forget a root's debounce timer. Stopping alone would leak the handle across roots.
---@param root string
---@return nil
local function release_timer(root)
    local s = store(root)
    if not s.timer then
        return
    end
    s.timer:stop()
    if not s.timer:is_closing() then
        s.timer:close()
    end
    s.timer = nil
end

--- Re-render the panel from the ring, coalescing a burst of appends into ONE repaint.
---@param root string
---@return nil
local function schedule_render(root)
    local s = store(root)
    if not s.pan then
        return
    end
    if not s.timer then
        s.timer = vim.uv.new_timer()
    end
    if not s.timer then
        return
    end
    s.timer:stop()
    s.timer:start(
        (config.dev_log or {}).render_debounce or 40,
        0,
        vim.schedule_wrap(function()
            local cur = store(root)
            if cur.pan and cur.pan.refresh then
                cur.pan.refresh()
                autoscroll(root)
            end
        end)
    )
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
    while #s.lines > max do
        table.remove(s.lines, 1)
    end
    if kind == "error" and cfg.notify_errors then
        vim.notify(line, vim.log.levels.ERROR, { title = "lvim-lang" })
    end
    -- The panel renders FROM the ring, so an append is complete once the ring holds it; the repaint is
    -- just a view update and can be coalesced.
    schedule_render(root)
end

--- Clear a root's dev-log buffer and ring.
---@param root string
---@return nil
function M.clear(root)
    store(root).lines = {}
    schedule_render(root)
end

--- Resolve the effective placement: a command-token override → the panel's own layout →
--- the global config.layout → "bottom".
---@param override? string
---@return string
local function resolve_layout(override)
    local dl = config.dev_log or {}
    return override or dl.layout or config.layout or "bottom"
end

--- The panel's title text: the per-root name a provider set (see `M.set_title`), else the configured
--- `dev_log.icon` + `dev_log.title`. The panel is shared by every language, so neither part is a literal.
---@param root string
---@return string
local function title_text(root)
    local dl = config.dev_log or {}
    local s = store(root)
    local icon = s.icon or dl.icon or ""
    local title = s.title or dl.title or "Dev Log"
    return icon ~= "" and (icon .. " " .. title) or title
end

--- The surface content provider: it renders the ring, so the panel never owns the data and any layout
--- shows the same log. Each row is highlighted by its KIND (normal / info / error).
---@param root string
---@return table  an lvim-ui.surface content provider
local function provider_for(root)
    return {
        filetype = FT,
        render = function()
            local s = store(root)
            if #s.lines == 0 then
                return { "  no output yet" }, { { 0, 0, 15, "LvimLangLogInfo" } }
            end
            local lines, hls = {}, {}
            for i, entry in ipairs(s.lines) do
                lines[i] = entry.text
                if #entry.text > 0 then
                    hls[#hls + 1] = { i - 1, 0, #entry.text, hl_for(entry.kind) }
                end
            end
            return lines, hls
        end,
        keys = function(map, pan)
            -- The panel hands back its own handles here: `pan.refresh` is what the debounced append calls,
            -- and `pan.win` is what the autoscroll follows.
            local s = store(root)
            s.pan = pan
            -- `map` is the surface's panel binder: (lhs, fn) on the panel buffer.
            local clear_key = ((config.dev_log or {}).keys or {}).clear
            if clear_key and clear_key ~= "" then
                map(clear_key, function()
                    M.clear(root)
                end)
            end
            -- Render whatever arrived while the panel was closed, and start at the tail.
            vim.schedule(function()
                if pan.refresh then
                    pan.refresh()
                end
                autoscroll(root)
            end)
        end,
        on_close = function()
            local s = store(root)
            release_timer(root)
            s.pan = nil
            s.surface = nil
        end,
    }
end

--- Open the dev-log panel for `root` in `layout`. Every placement is the SAME surface with a different
--- frame: a native split keeps the panel in the real window layout (so `<C-w>` navigation and redraw
--- behave), while "float" is the canonical centered frame.
---@param root string
---@param layout string
---@return nil
local function open_window(root, layout)
    local dl = config.dev_log or {}
    local s = store(root)
    local DOCK = { bottom = "below", top = "above", right = "right", left = "left" }
    local dock = DOCK[layout]
    local horiz = layout == "bottom" or layout == "top"

    ---@type table
    local cfg = {
        title = title_text(root),
        enter = dl.focus_on_open == true,
        persistent = true,
        content = { blocks = { { id = "devlog", provider = provider_for(root) } } },
        close_keys = { "q" },
    }
    if dock then
        cfg.mode = "split"
        cfg.native = true -- a REAL split: native <C-w> navigation and redraw, like any output pane
        cfg.dock = dock
        cfg.normal_hl = "NormalSB" -- a persistent pane wears the opaque sidebar background
        cfg.size = horiz and { height = { fixed = dl.height or 15 } } or { width = { fixed = dl.width or 60 } }
    else
        cfg.mode = "float"
        -- A log is a FIXED-SIZE scrollable pane, never content-fit: the ring holds up to `max_lines`, so
        -- letting the frame grow with the content would size it to thousands of rows (and letting it
        -- auto-fit a short log would open a one-row window).
        cfg.size = { height = { fixed = dl.height or 15 }, width = { fixed = dl.float_width or 0.7 } }
    end
    s.surface = surface.open(cfg)
end

--- Ensure the dev-log panel for a root is visible (idempotent). `layout` overrides the placement.
---@param root string
---@param layout? string
---@return nil
function M.open(root, layout)
    if not visible(root) then
        open_window(root, resolve_layout(layout))
    end
end

--- Close a root's dev-log panel (the ring survives — reopening shows the same output).
---@param root string
---@return nil
function M.close(root)
    local s = store(root)
    if s.surface and s.surface.close then
        s.surface.close()
    end
    release_timer(root)
    s.pan, s.surface = nil, nil
end

--- Toggle the dev-log panel for a root (placement: `layout` token → config).
---@param root string
---@param layout? string
---@return nil
function M.toggle(root, layout)
    if visible(root) then
        M.close(root)
        return
    end
    open_window(root, resolve_layout(layout))
end

return M
