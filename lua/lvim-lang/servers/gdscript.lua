-- lvim-lang.servers.gdscript: the bespoke server-config for GDScript (Godot). Godot's language
-- server is NOT a standalone binary — the running Godot EDITOR opens an LSP on 127.0.0.1:6005 (and a
-- Debug Adapter on 6006, wired separately in the provider's DATA.dap). So this server's `cmd` is a TCP
-- CLIENT — `vim.lsp.rpc.connect(host, port)` — which returns the transport Neovim uses in place of
-- spawning a process. lvim-ls' manager passes a non-table `cmd` straight to `vim.lsp.start` (it only
-- resolves a binary when `cmd` is a `{ argv }` list), so the TCP transport is honoured cleanly — no hack.
-- (Same mechanism as the Unison provider.)
--
-- CAVEAT (documented): the Godot editor must be open on the project so it owns port 6005 when the
-- first GDScript buffer opens; otherwise the connection fails.
--
---@module "lvim-lang.servers.gdscript"

local M = {}

--- The LSP client_capabilities fragment: lvim-cmp's when present, else the Neovim defaults.
---@return table
local function capabilities()
    local ok, cmp = pcall(require, "lvim-cmp")
    if ok and type(cmp.capabilities) == "function" then
        return cmp.capabilities()
    end
    return vim.lsp.protocol.make_client_capabilities()
end

--- The lvim-ls server-config: a TCP transport to the Godot editor's LSP (host/port overridable via
--- config.providers.gdscript.lsp.servers.gdscript.{host,port}). Because this on-disk module REPLACES
--- the generic declarative shim, it must also carry the DATA.dap the shim would otherwise attach — so
--- the Godot debug adapter (127.0.0.1:6006) is wired here from config.providers.gdscript.dap.
---@return table
function M.build()
    local popts_dap = (require("lvim-lang.config").providers.gdscript or {}).dap
    local root = vim.fs.root(0, { "project.godot", ".git" }) or vim.uv.cwd() or "."
    return {
        dap = popts_dap and require("lvim-lang.core.dap").build("gdscript", popts_dap, root) or nil,
        lsp = {
            root_patterns = { "project.godot", ".git" },
            ---@return table
            config = function()
                local se = (((require("lvim-lang.config").providers.gdscript or {}).lsp or {}).servers or {}).gdscript
                    or {}
                local host = se.host or "127.0.0.1"
                local port = tonumber(se.port) or 6005
                return {
                    -- A TCP transport to the LSP the running Godot editor opens — not a spawned binary.
                    cmd = vim.lsp.rpc.connect(host, port),
                    filetypes = { "gdscript" },
                    capabilities = capabilities(),
                }
            end,
        },
    }
end

-- On-disk server modules are required directly by lvim-ls and RETURN the config table (the generic
-- declarative shim is bypassed because this file exists on the runtimepath).
return M.build()
