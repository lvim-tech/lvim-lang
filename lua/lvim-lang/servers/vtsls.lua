-- lvim-lang.servers.vtsls: the lvim-ls server-config module for vtsls (the TypeScript/JS server).
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the TypeScript provider's
-- LSP catalog registers through core.lsp. lvim-lang does NOT own the LSP lifecycle — this module only
-- DESCRIBES the server; the canonical lvim-ls bootstrap starts and manages the client.
--
-- `lsp.config` is a FUNCTION (a seam lvim-ls supports): evaluated fresh per project root, so the
-- `vtsls` binary is resolved per root through the toolchain (a project-local install wins). vtsls is
-- the PRIMARY server: it carries the `dap` field (js-debug) and the per-filetype `efm` groups. When a
-- formatter (prettier) is active, vtsls' own formatting is switched off automatically (its on_attach,
-- set in the provider catalog) so prettier owns the buffer.
--
---@module "lvim-lang.servers.vtsls"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local ts_dap = require("lvim-lang.providers.typescript.dap")

local FILETYPES = { "typescript", "typescriptreact", "javascript", "javascriptreact" }

--- The TypeScript provider's config block.
---@return table
local function opts()
    return config.providers.typescript or {}
end

--- The vtsls server catalog entry (settings / init_options).
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.vtsls) or {}
end

--- Resolve the project root for the current buffer using the JS/TS root markers.
---@return string
local function current_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "package.json", "tsconfig.json", "jsconfig.json", ".git" }) or vim.fs.dirname(name)
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
    -- js-debug adapter + base node/chrome debug configurations (auto-registered with lvim-dap on attach).
    dap = ts_dap.spec(),
    -- Per-filetype formatter/linter routing (chosen efm tools only; empty when none selected).
    efm = catalog.efm_groups("typescript"),
    lsp = {
        root_patterns = { "tsconfig.json", "jsconfig.json", "package.json", ".git" },
        --- Built fresh per root so the vtsls binary tracks a project-local install.
        ---@return table
        config = function()
            local so = server_opts()
            local vtsls = toolchain.resolve("typescript", "vtsls", current_root()) or "vtsls"
            local cfg = {
                cmd = { vtsls, "--stdio" },
                filetypes = FILETYPES,
                capabilities = capabilities(),
                on_attach = catalog.lsp_on_attach("typescript", "vtsls"),
            }
            -- Only send non-empty tables: an empty Lua table encodes as a JSON ARRAY ([]), rejected.
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
