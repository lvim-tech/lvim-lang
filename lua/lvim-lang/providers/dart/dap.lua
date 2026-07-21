-- lvim-lang.providers.dart.dap: Flutter / Dart debugging through lvim-dap.
-- The Dart SDK ships the debug adapters: `dart debug_adapter` (pure Dart CLI) and
-- `flutter debug_adapter` (a Flutter app on a device, with debug-mode hot reload). Both are
-- registered as FACTORY adapters so the binary is resolved per project root through core.toolchain
-- (FVM/PATH) at launch time. The static adapters + base configurations are handed to lvim-ls via
-- the server config's `dap` field (auto-registered on attach); a dynamic provider additionally
-- offers a "Flutter (on <device>)" launch for the device selected in M6.
--
---@module "lvim-lang.providers.dart.dap"

local toolchain = require("lvim-lang.core.toolchain")
local coredap = require("lvim-lang.core.dap")

local M = {}

--- Resolve the project root for a buffer (dartls' markers).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "pubspec.yaml", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Build a factory adapter that resolves `tool`'s binary per root and runs `<bin> debug_adapter`.
---@param tool "dart"|"flutter"
---@return fun(callback: fun(adapter: table), cfg: table)
local function factory(tool)
    return function(callback, cfg)
        local root = (cfg and cfg.cwd) or vim.uv.cwd() or "."
        local bin = toolchain.resolve("dart", tool, root) or tool
        callback({
            type = "executable",
            command = bin,
            args = { "debug_adapter" },
            options = { source_filetype = "dart" },
        })
    end
end

--- The static `dap` field for the dartls server config (adapters + base configurations).
---@return table
function M.spec()
    return {
        adapters = {
            dart = factory("dart"),
            flutter = factory("flutter"),
        },
        configurations = {
            dart = {
                {
                    type = "flutter",
                    request = "launch",
                    name = "Flutter",
                    cwd = "${workspaceFolder}",
                    program = "lib/main.dart",
                },
                { type = "dart", request = "launch", name = "Dart", cwd = "${workspaceFolder}", program = "${file}" },
                { type = "flutter", request = "attach", name = "Flutter: Attach", cwd = "${workspaceFolder}" },
            },
        },
    }
end

--- Register the dynamic provider that offers a launch targeting the currently-selected device.
---@return nil
function M.register_provider()
    coredap.register_configs("lvim-lang-dart", function(bufnr)
        if vim.bo[bufnr].filetype ~= "dart" then
            return {}
        end
        local device = require("lvim-lang.providers.dart.devices").selected(root_of(bufnr))
        if not device then
            return {}
        end
        return {
            {
                type = "flutter",
                request = "launch",
                name = "Flutter (on " .. (device.name or device.id) .. ")",
                cwd = "${workspaceFolder}",
                program = "lib/main.dart",
                deviceId = device.id,
            },
        }
    end)
end

return M
