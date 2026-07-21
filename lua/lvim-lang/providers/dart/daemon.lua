-- lvim-lang.providers.dart.daemon: the Flutter `--machine` protocol semantics.
-- `flutter run --machine` / `flutter attach --machine` speak the Flutter daemon protocol: each
-- message is a single JSON object wrapped in a one-element array on its own line. This module is
-- the Flutter-specific half fed to the generic core.daemon: the line codec, and the event
-- handler that maps app.* / daemon.* events onto the dev log (and captures the appId / VM service
-- URI into the session record so the lifecycle commands can address the running app).
--
---@module "lvim-lang.providers.dart.daemon"

local log = require("lvim-lang.core.log")

local M = {}

-- Line codec: a protocol message is `[ {…} ]`; anything else is plain output (returns nil so
-- core.daemon routes it to on_line → the dev log).
M.codec = {
    ---@param line string
    ---@return table|nil
    decode = function(line)
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed:sub(1, 1) ~= "[" then
            return nil
        end
        local ok, arr = pcall(vim.json.decode, trimmed)
        if not ok or type(arr) ~= "table" then
            return nil
        end
        return arr[1]
    end,
    ---@param msg table
    ---@return string
    encode = function(msg)
        return vim.json.encode({ msg })
    end,
}

--- Build the on_event handler for a session: routes Flutter daemon events to the dev log and
--- records the appId / VM service URI onto `rec` (the session record in lvim-lang.state).
---@param root string
---@param rec table  the session record ({ session, appId?, vm_service?, … })
---@return fun(event: string, params: table)
function M.on_event(root, rec)
    return function(event, params)
        if event == "app.start" then
            rec.appId = params.appId
        elseif event == "app.started" then
            rec.vm_service = params.wsUri or rec.vm_service
            log.append(root, "app started", "info")
        elseif event == "app.debugPort" then
            rec.vm_service = params.wsUri or rec.vm_service
        elseif event == "app.log" then
            log.append(root, params.log or "", params.error and "error" or "normal")
        elseif event == "app.progress" then
            if params.message and params.message ~= "" then
                log.append(root, "… " .. params.message, "info")
            end
        elseif event == "app.stop" then
            log.append(root, "app stopped", "info")
        elseif event == "daemon.logMessage" then
            log.append(root, params.message or "", params.level == "error" and "error" or "normal")
        end
    end
end

return M
