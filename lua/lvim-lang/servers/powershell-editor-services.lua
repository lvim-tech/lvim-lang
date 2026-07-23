-- lvim-lang.servers.powershell-editor-services: the bespoke server-config for PowerShell Editor
-- Services (the PowerShell provider's LSP). PSES is not a plain binary — it is a set of PowerShell
-- modules launched by `pwsh` running Start-EditorServices.ps1 with the bundled-modules path and a
-- session-details file. That launch cannot be expressed as a static `cmd` in the provider DATA, so
-- this on-disk module (which the generic declarative shim yields to) builds it from the Mason
-- package layout. PSES also serves the DAP debug adapter over the same session.
--
---@module "lvim-lang.servers.powershell-editor-services"

local M = {}

--- The Mason package directory for powershell-editor-services (where Start-EditorServices.ps1 lives).
---@return string
local function pkg_dir()
    return vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", "powershell-editor-services")
end

--- The lvim-ls server-config for PSES: a `pwsh` invocation of the bundled Start-EditorServices.ps1 in
--- stdio mode. `pwsh` is resolved from PATH by lvim-ls; the script + bundled paths come from Mason.
---@return table
function M.build()
    local bundled = vim.fs.joinpath(pkg_dir(), "PowerShellEditorServices")
    local script = vim.fs.joinpath(bundled, "PowerShellEditorServices", "Start-EditorServices.ps1")
    local session = vim.fs.joinpath(vim.fn.stdpath("cache"), "powershell_es.session.json")
    local log = vim.fs.joinpath(vim.fn.stdpath("cache"), "powershell_es.log")
    return {
        lsp = {
            root_patterns = { ".git", "*.psd1", "*.psm1", "*.ps1" },
            ---@return table
            config = function()
                -- The whole PSES bootstrap is a single -Command fragment; -Stdio makes it speak LSP
                -- over stdin/stdout while still writing the session-details file PSES requires.
                local fragment = table.concat({
                    "& '" .. script .. "'",
                    "-HostName nvim -HostProfileId 'lvim-lang' -HostVersion '1.0.0'",
                    "-BundledModulesPath '" .. bundled .. "'",
                    "-SessionDetailsPath '" .. session .. "'",
                    "-LogPath '" .. log .. "' -LogLevel Normal",
                    "-Stdio -EnableConsoleRepl",
                }, " ")
                return {
                    cmd = { "pwsh", "-NoLogo", "-NoProfile", "-Command", fragment },
                    filetypes = { "ps1" },
                    capabilities = vim.lsp.protocol.make_client_capabilities(),
                }
            end,
        },
    }
end

-- On-disk server modules are required directly by lvim-ls and must RETURN the config table (the
-- generic declarative shim is bypassed because this file exists on the runtimepath).
return M.build()
