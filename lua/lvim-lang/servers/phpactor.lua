-- lvim-lang.servers.phpactor: the lvim-ls server-config module for phpactor — the OPT-IN alternative
-- PHP language server (select via providers.php.lsp.server = "phpactor"). Loaded by the lvim-ls
-- manager via the "lvim-lang.servers" dir prefix that the PHP provider's LSP catalog registers through
-- core.lsp. lvim-lang does NOT own the LSP lifecycle — this module only DESCRIBES the server; the
-- canonical lvim-ls bootstrap starts and manages the client.
--
-- `lsp.config` is a FUNCTION (a seam lvim-ls supports): evaluated fresh per project root, so the
-- phpactor binary is resolved per root through core.toolchain. phpactor is launched as a language
-- server over stdio (`phpactor language-server`). It formats PHP itself, so when an efm formatter is
-- active the client's formatting is switched off (catalog.lsp_on_attach). The php-debug-adapter
-- (Xdebug) `dap` field is shared with intelephense.
--
---@module "lvim-lang.servers.phpactor"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local php_dap = require("lvim-lang.providers.php.dap")

--- The PHP provider's config block.
---@return table
local function opts()
    return config.providers.php or {}
end

--- The phpactor server catalog entry, from config.providers.php.lsp.servers.phpactor.
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.phpactor) or {}
end

--- Resolve the project root for the current buffer using PHP's root markers.
---@return string
local function current_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "composer.json", ".git" }) or vim.fs.dirname(name)
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
    -- php-debug-adapter (Xdebug) adapter + base configurations (auto-registered with lvim-dap on attach).
    dap = php_dap.spec(),
    -- Per-filetype formatter/linter routing (chosen efm tools only; empty when none selected).
    efm = catalog.efm_groups("php"),
    lsp = {
        root_patterns = { "composer.json", ".git" },
        --- Built fresh per root so the phpactor binary tracks the project's toolchain.
        ---@return table
        config = function()
            local so = server_opts()
            local phpactor = toolchain.resolve("php", "phpactor", current_root()) or "phpactor"
            local cfg = {
                cmd = so.cmd or { phpactor, "language-server" },
                filetypes = { "php" },
                capabilities = capabilities(),
                -- Hand formatting to efm when a formatter is active for the buffer (else phpactor
                -- formats). Composes any user server on_attach.
                on_attach = catalog.lsp_on_attach("php", "phpactor"),
            }
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
