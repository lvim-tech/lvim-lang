-- lvim-lang.providers.dart.devices: Flutter device / emulator selection.
-- Devices and emulators are listed by talking to a SHORT-LIVED `flutter daemon` session (the
-- same protocol as `flutter run --machine`, via core.daemon): device.getDevices /
-- emulator.getEmulators, and emulator.launch to boot one. The chosen device is remembered per
-- project root — in lvim-lang.state for the session and, when lvim-utils.store is available, on
-- disk — so `:LvimLang run` targets it and the statusline can show it.
--
---@module "lvim-lang.providers.dart.devices"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local daemon = require("lvim-lang.core.daemon")
local proto = require("lvim-lang.providers.dart.daemon")
local ui = require("lvim-lang.core.ui")
local state = require("lvim-lang.state")

--- The Dart provider's configured icons.
---@return table
local function icons()
    return (config.providers.dart and config.providers.dart.icons) or {}
end

local TITLE = { title = "lvim-lang" }

local M = {}

-- On-disk persistence of the per-root device choice, via the shared lvim-lang store (guarded —
-- degrades to session-only when lvim-utils.store is unavailable).
local db = require("lvim-lang.core.store").get()

--- The resolved flutter binary for a root.
---@param root string
---@return string
local function flutter(root)
    return toolchain.resolve("dart", "flutter", root) or "flutter"
end

--- Run `fn(session)` against a short-lived `flutter daemon` once it is connected, with a
--- safety stop so a daemon that never connects cannot leak.
---@param root string
---@param fn fun(session: LvimLangDaemonSession)
---@return nil
local function with_daemon(root, fn)
    local session
    session = daemon.start({
        cmd = { flutter(root), "daemon" },
        cwd = root,
        codec = proto.codec,
        on_event = function(event)
            if event == "daemon.connected" and session then
                fn(session)
            end
        end,
    })
    if not session then
        vim.notify("lvim-lang: could not start `flutter daemon`", vim.log.levels.WARN, TITLE)
        return
    end
    vim.defer_fn(function()
        if session and session:alive() then
            session:stop()
        end
    end, 5000)
end

--- Fetch a list via one daemon `method`, then stop the daemon.
---@param root string
---@param method string
---@param cb fun(items: table[])
---@return nil
local function query_list(root, method, cb)
    with_daemon(root, function(session)
        session:request(method, nil, function(_, result)
            session:stop()
            cb(type(result) == "table" and result or {})
        end)
    end)
end

--- Remember the selected device for a root (session state + disk when available).
---@param root string
---@param device { id: string, name?: string }
---@return nil
function M.remember(root, device)
    state.selected[root] = state.selected[root] or {}
    state.selected[root].device = device
    if db then
        local all = db.devices or {}
        all[root] = device
        db.devices = all
    end
end

--- The selected device for a root (session state, else the persisted choice, hydrated).
---@param root string
---@return { id: string, name?: string }|nil
function M.selected(root)
    local sel = state.selected[root]
    if sel and sel.device then
        return sel.device
    end
    if db and db.devices and db.devices[root] then
        state.selected[root] = state.selected[root] or {}
        state.selected[root].device = db.devices[root]
        return db.devices[root]
    end
    return nil
end

--- `:LvimLang devices` — list connected devices and remember the chosen one.
---@param _args string[]
---@param ctx table  { provider, root, bufnr }
---@return nil
function M.pick_device(_args, ctx)
    local root = ctx.root
    query_list(root, "device.getDevices", function(devices)
        if #devices == 0 then
            vim.notify("lvim-lang: no devices found", vim.log.levels.INFO, TITLE)
            return
        end
        local current = M.selected(root)
        local ic = icons()
        local items, current_idx = {}, nil
        for i, d in ipairs(devices) do
            items[i] = {
                label = d.name or d.id,
                icon = d.emulator and (ic.emulator or "󰄰") or (ic.device or "󰄶"),
                device = d,
            }
            if current and current.id == d.id then
                current_idx = i
            end
        end
        ui.pick({ title = "Flutter devices", items = items, current = current_idx }, function(item)
            if not item then
                return
            end
            M.remember(root, { id = item.device.id, name = item.device.name })
            vim.notify("lvim-lang: device → " .. (item.device.name or item.device.id), vim.log.levels.INFO, TITLE)
        end)
    end)
end

--- `:LvimLang emulators` — list emulators and boot the chosen one.
---@param _args string[]
---@param ctx table  { provider, root, bufnr }
---@return nil
function M.pick_emulator(_args, ctx)
    local root = ctx.root
    query_list(root, "emulator.getEmulators", function(emulators)
        if #emulators == 0 then
            vim.notify("lvim-lang: no emulators found", vim.log.levels.INFO, TITLE)
            return
        end
        local ic = icons()
        local items = {}
        for i, e in ipairs(emulators) do
            items[i] = { label = e.name or e.id, icon = ic.emulator or "󰄰", emulator = e }
        end
        ui.pick({ title = "Flutter emulators", items = items }, function(item)
            if not item then
                return
            end
            with_daemon(root, function(session)
                session:request("emulator.launch", { emulatorId = item.emulator.id }, function()
                    session:stop()
                end)
            end)
            vim.notify("lvim-lang: launching " .. (item.emulator.name or item.emulator.id), vim.log.levels.INFO, TITLE)
        end)
    end)
end

return M
