-- lvim-lang.providers.fsharp.dap: F# / .NET debugging through lvim-dap, backed by netcoredbg.
-- The static adapter + base launch/attach configurations are handed to lvim-ls via the language
-- server config's `dap` field (auto-registered with lvim-dap on attach). The `netcoredbg` binary is
-- resolved per project root through core.toolchain at launch time. `:LvimLang debug` continues /
-- starts a session; the launch config prompts for the built DLL (default `bin/Debug/…`), the attach
-- config picks a running process. Per-test debugging is not offered — the .NET test host is launched
-- out-of-process, so a test is debugged by attaching to its `dotnet test` process with the attach
-- config (documented).
--
---@module "lvim-lang.providers.fsharp.dap"

local toolchain = require("lvim-lang.core.toolchain")

local TITLE = { title = "lvim-lang" }

local M = {}

--- Resolve the netcoredbg binary: an explicit config path → the mason install → PATH.
---@return string
local function netcoredbg_bin()
    local root = vim.uv.cwd() or "."
    local resolved = toolchain.resolve("fsharp", "netcoredbg", root)
    return resolved or "netcoredbg"
end

--- The netcoredbg DAP adapter (VS Code protocol interpreter over stdio).
---@return table
local function adapter()
    return {
        type = "executable",
        command = netcoredbg_bin(),
        args = { "--interpreter=vscode" },
    }
end

--- The static `dap` field for the language server config (adapter + base configurations).
---@return table
function M.spec()
    return {
        adapters = { coreclr = adapter() },
        configurations = {
            fsharp = {
                {
                    type = "coreclr",
                    request = "launch",
                    name = "Launch (pick a built DLL)",
                    program = function()
                        local root = require("lvim-lang.providers.fsharp.tasks").root()
                        return vim.fn.input("Path to dll: ", root .. "/bin/Debug/", "file")
                    end,
                    cwd = "${workspaceFolder}",
                    stopAtEntry = false,
                },
                {
                    type = "coreclr",
                    request = "attach",
                    name = "Attach to process",
                    processId = function()
                        local ok, dap_utils = pcall(require, "dap.utils")
                        if ok and dap_utils and dap_utils.pick_process then
                            return dap_utils.pick_process()
                        end
                        return tonumber(vim.fn.input("Process id: "))
                    end,
                },
            },
        },
    }
end

--- `:LvimLang debug` — continue / start a debug session (lvim-dap picks a configuration).
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
