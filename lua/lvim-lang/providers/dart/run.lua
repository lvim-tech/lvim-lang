-- lvim-lang.providers.dart.run: the Flutter run lifecycle.
-- Owns a single `flutter run --machine` (or `flutter attach --machine`) session per project
-- root, driven through the generic core.daemon with the Flutter protocol from
-- providers.dart.daemon. Hot reload / restart / quit / detach address the running app by its
-- appId. The session record lives in lvim-lang.state.sessions[root]; its non-protocol output and
-- app.log stream into the shared core.log dev-log panel.
--
---@module "lvim-lang.providers.dart.run"

local toolchain = require("lvim-lang.core.toolchain")
local daemon = require("lvim-lang.core.daemon")
local log = require("lvim-lang.core.log")
local state = require("lvim-lang.state")
local runcfg = require("lvim-lang.core.runcfg")
local proto = require("lvim-lang.providers.dart.daemon")
local devices = require("lvim-lang.providers.dart.devices")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The resolved flutter binary for a root.
---@param root string
---@return string
local function flutter(root)
    return toolchain.resolve("dart", "flutter", root) or "flutter"
end

--- Map a run-config table (from .lvim/lang/run.lua) to `flutter run` arguments.
---@param cfg table
---@return string[]
local function config_args(cfg)
    local a = {}
    local mode = cfg.mode or cfg.flutter_mode
    if mode == "profile" then
        a[#a + 1] = "--profile"
    elseif mode == "release" then
        a[#a + 1] = "--release"
    end
    if cfg.flavor then
        vim.list_extend(a, { "--flavor", tostring(cfg.flavor) })
    end
    if cfg.target then
        vim.list_extend(a, { "--target", tostring(cfg.target) })
    end
    if type(cfg.dart_define) == "table" then
        for k, v in pairs(cfg.dart_define) do
            a[#a + 1] = "--dart-define=" .. k .. "=" .. tostring(v)
        end
    end
    if cfg.dart_define_from_file then
        a[#a + 1] = "--dart-define-from-file=" .. tostring(cfg.dart_define_from_file)
    end
    if type(cfg.args) == "table" then
        vim.list_extend(a, cfg.args)
    end
    return a
end

--- The live session record for a root, if its process is still alive.
---@param root string
---@return table|nil
local function live(root)
    local rec = state.sessions[root]
    if rec and rec.session and rec.session:alive() then
        return rec
    end
    return nil
end

--- Start a Flutter session (`run` or `attach`) for the buffer's root.
---@param ctx table  { provider, root, bufnr }
---@param mode "run"|"attach"
---@param args string[]  extra flutter args (from the command line, appended after the run-config flags)
---@return nil
local function launch(ctx, mode, args)
    local root = ctx.root
    if live(root) then
        -- Already running — reveal the dev log rather than silently no-op'ing.
        log.open(root)
        vim.notify("lvim-lang: already running here — use reload/restart/quit", vim.log.levels.WARN, TITLE)
        return
    end
    local cmd = { flutter(root), mode, "--machine" }
    -- Device: an active run config's `device` overrides the interactively-selected one.
    local active = runcfg.active(root)
    local device = devices.selected(root)
    local device_id = (active and active.device) or (device and device.id)
    if device_id then
        vim.list_extend(cmd, { "-d", device_id })
    end
    -- Run-config flags apply to `run` (not `attach`).
    if mode == "run" and active then
        vim.list_extend(cmd, config_args(active))
    end
    vim.list_extend(cmd, args or {})

    local rec = { device = device, run_config = active and active.name }
    local session = daemon.start({
        cmd = cmd,
        cwd = root,
        codec = proto.codec,
        on_event = proto.on_event(root, rec),
        on_line = function(line)
            log.append(root, line, "normal")
        end,
        on_exit = function(code)
            log.append(root, ("flutter %s exited (%d)"):format(mode, code), "info")
            state.sessions[root] = nil
        end,
    })
    if not session then
        vim.notify("lvim-lang: failed to start `flutter " .. mode .. "`", vim.log.levels.ERROR, TITLE)
        return
    end
    rec.session = session
    state.sessions[root] = rec
    log.open(root)
    vim.notify(
        "lvim-lang: flutter " .. mode .. (device and (" on " .. (device.name or device.id)) or ""),
        vim.log.levels.INFO,
        TITLE
    )
end

--- `:LvimLang run [args…]` — always opens the device picker to choose the target, then launches on
--- it (the last-used device pre-focused). There is no separate device command.
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    devices.choose(ctx, function(device)
        if device then
            launch(ctx, "run", args)
        end
    end)
end

--- `:LvimLang attach [args…]` — attach to an already-running app.
---@param args string[]
---@param ctx table
---@return nil
function M.attach(args, ctx)
    launch(ctx, "attach", args)
end

--- Send an app.restart to the running app (hot reload / hot restart).
---@param ctx table
---@param full boolean  true = hot restart, false = hot reload
---@param label string
---@return nil
local function restart(ctx, full, label)
    local rec = live(ctx.root)
    if not rec or not rec.appId then
        vim.notify("lvim-lang: no running app", vim.log.levels.WARN, TITLE)
        return
    end
    rec.session:request("app.restart", { appId = rec.appId, fullRestart = full }, function(err)
        if err then
            log.append(ctx.root, label .. " failed: " .. vim.inspect(err), "error")
        end
    end)
    vim.notify("lvim-lang: " .. label, vim.log.levels.INFO, TITLE)
end

--- `:LvimLang reload` — hot reload.
---@param _args string[]
---@param ctx table
---@return nil
function M.reload(_args, ctx)
    restart(ctx, false, "hot reload")
end

--- `:LvimLang restart` — hot restart.
---@param _args string[]
---@param ctx table
---@return nil
function M.restart(_args, ctx)
    restart(ctx, true, "hot restart")
end

--- Stop the app and end the session (`quit`) or just detach and end it (`detach`).
---@param ctx table
---@param method "app.stop"|"app.detach"
---@param label string
---@return nil
local function terminate(ctx, method, label)
    local rec = live(ctx.root)
    if not rec then
        vim.notify("lvim-lang: nothing running here", vim.log.levels.WARN, TITLE)
        return
    end
    if rec.appId then
        rec.session:request(method, { appId = rec.appId })
    end
    vim.defer_fn(function()
        if state.sessions[ctx.root] == rec then
            rec.session:stop()
            state.sessions[ctx.root] = nil
        end
    end, 300)
    vim.notify("lvim-lang: " .. label, vim.log.levels.INFO, TITLE)
end

--- `:LvimLang quit` — stop the running app and end the session.
---@param _args string[]
---@param ctx table
---@return nil
function M.quit(_args, ctx)
    terminate(ctx, "app.stop", "stopping app")
end

--- `:LvimLang detach` — detach from the app (leave it running) and end the session.
---@param _args string[]
---@param ctx table
---@return nil
function M.detach(_args, ctx)
    terminate(ctx, "app.detach", "detaching")
end

-- Placement tokens accepted by `:LvimLang log` (a layout override for this open).
local LOG_LAYOUTS = { bottom = true, top = true, area = true, float = true, right = true, left = true }

--- `:LvimLang log [toggle|clear] [bottom|top|area|float|right|left]` — toggle (default) or clear
--- the dev-log panel; a placement token overrides the configured layout for this open.
---@param args string[]
---@param ctx table
---@return nil
function M.log(args, ctx)
    local sub, layout
    for _, a in ipairs(args) do
        if LOG_LAYOUTS[a] then
            layout = a
        elseif a == "clear" or a == "toggle" then
            sub = a
        end
    end
    if sub == "clear" then
        log.clear(ctx.root)
        return
    end
    log.toggle(ctx.root, layout)
end

return M
