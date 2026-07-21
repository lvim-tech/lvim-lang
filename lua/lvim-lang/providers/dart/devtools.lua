-- lvim-lang.providers.dart.devtools: launch Dart DevTools for the running app.
-- `dart devtools --machine` starts the DevTools server and emits a `server.started` event with
-- the host/port; combined with the running session's VM service URI it yields the full DevTools
-- URL, which is copied to the clipboard and opened in the browser. The server session is kept in
-- state.devtools[root] so it stays up. (VM-service INTROSPECTION — inspect widget, brightness,
-- platform — is M9b, a separate WebSocket client.)
--
---@module "lvim-lang.providers.dart.devtools"

local toolchain = require("lvim-lang.core.toolchain")
local daemon = require("lvim-lang.core.daemon")
local state = require("lvim-lang.state")

local TITLE = { title = "lvim-lang" }

local M = {}

-- DevTools --machine speaks newline-delimited JSON OBJECTS (not the array-wrapped daemon frames).
local codec = {
    ---@param line string
    ---@return table|nil
    decode = function(line)
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed:sub(1, 1) ~= "{" then
            return nil
        end
        local ok, obj = pcall(vim.json.decode, trimmed)
        return ok and obj or nil
    end,
    ---@param msg table
    ---@return string
    encode = function(msg)
        return vim.json.encode(msg)
    end,
}

--- `:LvimLang devtools` — start the DevTools server and open its URL (with the running app's VM
--- service URI when a session is live).
---@param _args string[]
---@param ctx table  { provider, root, bufnr }
---@return nil
function M.open(_args, ctx)
    local root = ctx.root
    state.devtools = state.devtools or {}
    if state.devtools[root] and state.devtools[root]:alive() then
        vim.notify("lvim-lang: DevTools already running for this project", vim.log.levels.INFO, TITLE)
        return
    end
    local dart = toolchain.resolve("dart", "dart", root) or "dart"
    local session_rec = state.sessions[root]
    local vm = session_rec and session_rec.vm_service

    local session
    session = daemon.start({
        cmd = { dart, "devtools", "--machine" },
        cwd = root,
        codec = codec,
        on_event = function(event, params)
            if event == "server.started" then
                local url = ("http://%s:%s"):format(params.host or "127.0.0.1", tostring(params.port))
                local full = vm and (url .. "?uri=" .. vm) or url
                pcall(vim.fn.setreg, "+", full)
                vim.notify("lvim-lang: DevTools " .. full .. " (copied)", vim.log.levels.INFO, TITLE)
                pcall(vim.ui.open, full)
            end
        end,
        on_exit = function()
            if state.devtools then
                state.devtools[root] = nil
            end
        end,
    })
    if not session then
        vim.notify("lvim-lang: failed to start DevTools", vim.log.levels.ERROR, TITLE)
        return
    end
    state.devtools[root] = session
    vim.notify("lvim-lang: starting DevTools…", vim.log.levels.INFO, TITLE)
end

return M
