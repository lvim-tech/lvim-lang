-- lvim-lang.servers.gopls: the lvim-ls server-config module for gopls (the Go language server).
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the Go provider's LSP
-- catalog registers through core.lsp (register_catalog fans the chosen servers out). lvim-lang does
-- NOT own the LSP lifecycle — this module only DESCRIBES the server; the canonical lvim-ls bootstrap
-- starts and manages the client.
--
-- `lsp.config` is a FUNCTION (a seam lvim-ls supports): evaluated fresh per project root, so the
-- `gopls` binary is resolved per root through core.toolchain (a version-managed toolchain in one
-- project and the PATH one in another both start correctly). The `efm` field is PER-FILETYPE
-- (core.catalog.efm_groups): the chosen formatter/linter land on their own filetype — gofumpt on
-- `go`, an opt-in linter on `gomod` — never smeared across all of the server's filetypes.
--
---@module "lvim-lang.servers.gopls"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local go_dap = require("lvim-lang.providers.go.dap")

--- The Go provider's config block.
---@return table
local function opts()
    return config.providers.go or {}
end

--- The gopls server catalog entry (settings / init_options), from
--- config.providers.go.lsp.servers.gopls.
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.gopls) or {}
end

--- Resolve the project root for the current buffer using gopls' root markers.
---@return string
local function current_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "go.work", "go.mod", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
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
    -- Delve adapter + base go debug configurations (auto-registered with lvim-dap on attach).
    dap = go_dap.spec(),
    -- Per-filetype formatter/linter routing (chosen tools only; empty when none selected).
    efm = catalog.efm_groups("go"),
    lsp = {
        root_patterns = { "go.work", "go.mod", ".git" },
        --- Built fresh per root so the gopls binary tracks the project's toolchain (version manager / PATH).
        ---@return table
        config = function()
            local so = server_opts()
            local gopls = toolchain.resolve("go", "gopls", current_root()) or "gopls"
            local cfg = {
                cmd = { gopls },
                filetypes = { "go", "gomod", "gowork", "gotmpl" },
                capabilities = capabilities(),
                -- Hand formatting to efm when a formatter is active for the buffer's ft (else gopls
                -- formats — gofumpt = true). Composes any user server on_attach.
                on_attach = catalog.lsp_on_attach("go", "gopls"),
            }
            -- Only send settings / init_options when non-empty: an empty Lua table encodes as a JSON
            -- ARRAY ([]), which gopls rejects ("invalid options type []interface {}"). The catalog
            -- stores gopls' settings already nested under the `gopls` key.
            if so.settings and next(so.settings) then
                cfg.settings = so.settings
            end
            if so.init_options and next(so.init_options) then
                cfg.init_options = so.init_options
            end
            return cfg
        end,
    },
}
