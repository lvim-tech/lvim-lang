-- lvim-lang.servers.unison: the lvim-ls server-config module for the Unison language server.
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the Unison provider's
-- LSP catalog registers through core.lsp. lvim-lang does NOT own the LSP lifecycle — this module
-- only DESCRIBES the server; the canonical lvim-ls bootstrap starts and manages the client.
--
-- UNISON IS UNUSUAL. There is no standalone Unison LSP binary to launch: the language server is
-- served, over TCP, by a RUNNING UCM (the Unison Codebase Manager). When you start `ucm`
-- interactively in your codebase it opens an LSP server on 127.0.0.1:5757 by default (override the
-- port with the `UNISON_LSP_PORT` env var, or disable it with `UNISON_LSP_ENABLED=false`). So this
-- server's `cmd` is NOT a launched process but a TCP CLIENT — `vim.lsp.rpc.connect(host, port)`,
-- which returns the transport function Neovim uses in place of spawning a binary. lvim-ls'
-- manager passes a non-table `cmd` straight through to `vim.lsp.start` (it only tries to resolve a
-- binary when `cmd` is a `{ argv }` list), so the TCP transport is honoured cleanly — no hack.
--
-- CAVEAT (documented, and OPEN as an enhancement): a running UCM must already own the port when the
-- first Unison buffer opens. If UCM is not up, the connection fails and lvim-ls latches the server
-- off for that root — start UCM, then re-open the buffer or restart the client. There is no launched
-- process for lvim-ls to health-resolve, so the toolchain's `ucm` presence check + a requirement
-- notice are what surface "you forgot to start UCM".
--
---@module "lvim-lang.servers.unison"

local config = require("lvim-lang.config")

--- The Unison provider's config block.
---@return table
local function opts()
    return config.providers.unison or {}
end

--- The unison server catalog entry (settings / init_options), from
--- config.providers.unison.lsp.servers.unison.
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.unison) or {}
end

--- The LSP client_capabilities fragment: lvim-cmp's when present, else the Neovim defaults.
---@return table
local function capabilities()
    local ok, cmp = pcall(require, "lvim-cmp")
    if ok and type(cmp.capabilities) == "function" then
        return cmp.capabilities()
    end
    return vim.lsp.protocol.make_client_capabilities()
end

return {
    lsp = {
        root_patterns = { ".git" },
        --- Built fresh per root so the host/port track the live config (UNISON_LSP_PORT / lsp_port).
        ---@return table
        config = function()
            local o = opts()
            local so = server_opts()
            local host = o.lsp_host or "127.0.0.1"
            local port = tonumber(o.lsp_port) or 5757
            local cfg = {
                -- A TCP transport to the LSP server the user's running UCM opens — not a spawned binary.
                cmd = vim.lsp.rpc.connect(host, port),
                filetypes = { "unison" },
                capabilities = capabilities(),
            }
            -- Only send non-empty tables: an empty Lua table encodes as a JSON ARRAY ([]), which
            -- servers reject.
            if so.init_options and next(so.init_options) then
                cfg.init_options = so.init_options
            end
            if so.settings and next(so.settings) then
                cfg.settings = so.settings
            end
            return cfg
        end,
    },
}
