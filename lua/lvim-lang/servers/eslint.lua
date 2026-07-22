-- lvim-lang.servers.eslint: the lvim-ls server-config module for the eslint language server.
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the TypeScript provider's
-- LSP catalog registers through core.lsp. lvim-lang does NOT own the LSP lifecycle — this module only
-- DESCRIBES the server; the canonical lvim-ls bootstrap starts and manages the client.
--
-- vscode-eslint-language-server attaches ALONGSIDE vtsls (the types server): it owns lint diagnostics
-- and the fix-all code action, while formatting stays with prettier (`format = false` in its settings,
-- and its formatting is also switched off by its catalog on_attach when a formatter is active). It
-- needs `eslint` installed in the project (node_modules) to actually lint; with none it no-ops. The
-- binary is resolved per root through the toolchain. No `dap` / `efm` here — those ride on the PRIMARY
-- server (vtsls).
--
---@module "lvim-lang.servers.eslint"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")

local FILETYPES = { "typescript", "typescriptreact", "javascript", "javascriptreact" }

--- The TypeScript provider's config block.
---@return table
local function opts()
    return config.providers.typescript or {}
end

--- The eslint server catalog entry (settings).
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.eslint) or {}
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
    lsp = {
        root_patterns = {
            ".eslintrc",
            ".eslintrc.js",
            ".eslintrc.cjs",
            ".eslintrc.json",
            "eslint.config.js",
            "eslint.config.mjs",
            "package.json",
            ".git",
        },
        --- Built fresh per root so the eslint server binary is resolved per project.
        ---@return table
        config = function()
            local so = server_opts()
            local eslint = toolchain.resolve("typescript", "eslint-lsp", current_root())
                or "vscode-eslint-language-server"
            local cfg = {
                cmd = { eslint, "--stdio" },
                filetypes = FILETYPES,
                capabilities = capabilities(),
                on_attach = catalog.lsp_on_attach("typescript", "eslint"),
            }
            -- Only send non-empty tables: an empty Lua table encodes as a JSON ARRAY ([]), rejected.
            -- The server requests the `eslint` configuration section, matched from settings.eslint.
            if so.settings and next(so.settings) then
                cfg.settings = so.settings
            end
            return cfg
        end,
    },
}
