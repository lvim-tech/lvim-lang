-- lvim-lang.providers.dart.vmservice: Flutter VM-service introspection (widget inspector,
-- debug paint, brightness, target platform).
-- Rather than open a raw VM-service WebSocket, these Flutter service extensions are invoked
-- THROUGH the running `flutter run --machine` daemon, which proxies them via its
-- `app.callServiceExtension` method. So this reuses the existing core.daemon session (no new
-- transport) — the clean seam when the app was started by our runner. Boolean toggles keep their
-- state on the session record so a second call flips them.
--
---@module "lvim-lang.providers.dart.vmservice"

local config = require("lvim-lang.config")
local state = require("lvim-lang.state")
local ui = require("lvim-lang.core.ui")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The running session record for a root (with a live app + appId), or nil (with a notice).
---@param ctx table  { root, … }
---@return table|nil
local function running_app(ctx)
    local rec = state.sessions[ctx.root]
    if rec and rec.session and rec.session:alive() and rec.appId then
        rec.vm = rec.vm or {}
        return rec
    end
    vim.notify("lvim-lang: no running app — start :LvimLang run", vim.log.levels.WARN, TITLE)
    return nil
end

--- Invoke a Flutter service extension through the daemon.
---@param rec table
---@param method string
---@param params table
---@param cb? fun(err: any, result: any)
---@return nil
local function call(rec, method, params, cb)
    rec.session:request(
        "app.callServiceExtension",
        { appId = rec.appId, methodName = method, params = params or {} },
        cb
    )
end

--- Toggle a boolean service extension, tracking its state on the session record.
---@param ctx table
---@param key string      the state key on rec.vm
---@param method string   the service-extension method
---@param label string    human label for the notification
---@return nil
local function toggle_bool(ctx, key, method, label)
    local rec = running_app(ctx)
    if not rec then
        return
    end
    rec.vm[key] = not rec.vm[key]
    call(rec, method, { enabled = rec.vm[key] })
    vim.notify("lvim-lang: " .. label .. " " .. (rec.vm[key] and "on" or "off"), vim.log.levels.INFO, TITLE)
end

--- `:LvimLang inspect` — toggle the widget inspector overlay.
---@param _args string[]
---@param ctx table
---@return nil
function M.inspect_widget(_args, ctx)
    toggle_bool(ctx, "inspector", "ext.flutter.inspector.show", "widget inspector")
end

--- `:LvimLang paint` — toggle debug paint (visual layout debugging).
---@param _args string[]
---@param ctx table
---@return nil
function M.visual_debug(_args, ctx)
    toggle_bool(ctx, "debugPaint", "ext.flutter.debugPaint", "debug paint")
end

--- `:LvimLang brightness` — flip the app between light and dark brightness.
---@param _args string[]
---@param ctx table
---@return nil
function M.toggle_brightness(_args, ctx)
    local rec = running_app(ctx)
    if not rec then
        return
    end
    rec.vm.brightness = (rec.vm.brightness == "Brightness.dark") and "Brightness.light" or "Brightness.dark"
    call(rec, "ext.flutter.brightnessOverride", { value = rec.vm.brightness })
    vim.notify("lvim-lang: brightness " .. rec.vm.brightness:gsub("Brightness%.", ""), vim.log.levels.INFO, TITLE)
end

--- `:LvimLang platform` — override the app's target platform (picked through lvim-ui).
---@param _args string[]
---@param ctx table
---@return nil
function M.target_platform(_args, ctx)
    local rec = running_app(ctx)
    if not rec then
        return
    end
    local icon = ((config.providers.dart and config.providers.dart.icons) or {}).platform or "󰀲"
    local items = {}
    for _, p in ipairs({ "android", "iOS", "fuchsia", "linux", "macOS", "windows" }) do
        items[#items + 1] = { label = p, icon = icon }
    end
    ui.pick({ title = "Target platform", items = items }, function(item)
        if not item then
            return
        end
        call(rec, "ext.flutter.platformOverride", { value = item.label })
        vim.notify("lvim-lang: platform → " .. item.label, vim.log.levels.INFO, TITLE)
    end)
end

return M
