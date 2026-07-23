-- lvim-lang.providers.php.dap: PHP debugging through lvim-dap, backed by php-debug-adapter (Xdebug).
-- The static adapter + base configurations are handed to lvim-ls via the intelephense server config's
-- `dap` field (auto-registered with lvim-dap on attach). php-debug-adapter (the mason `php-debug-
-- adapter` package, VS Code's vscode-php-debug over stdio) speaks DAP to Xdebug: unlike a launch-only
-- debugger, PHP debugging is CONNECTION-driven — the adapter LISTENS on a port for an Xdebug session
-- opened by the PHP runtime, so the primary configuration is a "listen" one; a "launch current script"
-- configuration also runs the open file under the CLI runtime with Xdebug triggered.
--
-- IMPORTANT: Xdebug must be installed and enabled in the PHP RUNTIME itself (the user's own PHP, not a
-- mason package): `pecl install xdebug`, then in php.ini `xdebug.mode=debug` and
-- `xdebug.start_with_request=yes` (Xdebug 3, default client port 9003). Without it the runtime never
-- opens a debug connection and the listener simply waits.
--
---@module "lvim-lang.providers.php.dap"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The PHP provider's config block.
---@return table
local function opts()
    return config.providers.php or {}
end

--- Resolve the php-debug-adapter binary: an explicit config path → the mason install → PATH.
---@return string
local function adapter_bin()
    local root = vim.uv.cwd() or "."
    local o = opts()
    if o.php_debug_adapter_path and vim.fn.executable(o.php_debug_adapter_path) == 1 then
        return o.php_debug_adapter_path
    end
    local resolved = toolchain.resolve("php", "php-debug-adapter", root)
    if resolved then
        return resolved
    end
    local p = vim.fn.exepath("php-debug-adapter")
    return p ~= "" and p or "php-debug-adapter"
end

--- The php-debug-adapter DAP adapter (VS Code php-debug over stdio, mediating Xdebug ↔ DAP).
---@return table
local function adapter()
    return {
        type = "executable",
        command = adapter_bin(),
        args = {},
    }
end

--- The static `dap` field for the intelephense server config (adapter + base configurations). The
--- listen port defaults to Xdebug 3's 9003 (overridable via providers.php.debug_port).
---@return table
function M.spec()
    local port = opts().debug_port or 9003
    local php = toolchain.resolve("php", "php", vim.uv.cwd() or ".") or "php"
    return {
        adapters = { php = adapter() },
        configurations = {
            php = {
                {
                    -- The canonical Xdebug flow: the adapter LISTENS; the PHP runtime (a web request or
                    -- CLI invocation with Xdebug enabled) connects back to this port.
                    type = "php",
                    request = "launch",
                    name = "Listen for Xdebug (:" .. port .. ")",
                    port = port,
                },
                {
                    -- Run the file in the current buffer under the CLI runtime with Xdebug triggered.
                    type = "php",
                    request = "launch",
                    name = "Launch current script",
                    program = "${file}",
                    cwd = "${fileDirname}",
                    port = port,
                    runtimeExecutable = php,
                    runtimeArgs = { "-dxdebug.start_with_request=yes" },
                },
            },
        },
    }
end

--- `:LvimLang debug` — continue / start a debug session (lvim-dap picks a configuration: the Xdebug
--- listener or the current-script launch).
---@param _args string[]
---@param _ctx table
---@return nil
function M.debug(_args, _ctx)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok then
        vim.notify("lvim-lang: lvim-dap not available", vim.log.levels.WARN, TITLE)
        return
    end
    dap.continue()
end

return M
