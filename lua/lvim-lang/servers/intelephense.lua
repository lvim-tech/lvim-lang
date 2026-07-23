-- lvim-lang.servers.intelephense: the lvim-ls server-config module for intelephense (the default PHP
-- language server). Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the PHP
-- provider's LSP catalog registers through core.lsp (register_catalog fans the chosen servers out).
-- lvim-lang does NOT own the LSP lifecycle — this module only DESCRIBES the server; the canonical
-- lvim-ls bootstrap starts and manages the client.
--
-- `lsp.config` is a FUNCTION (a seam lvim-ls supports): evaluated fresh per project root, so the
-- intelephense binary is resolved per root through core.toolchain (a version-managed toolchain and
-- the PATH one both start correctly). intelephense is launched over stdio (`intelephense --stdio`);
-- its premium licence key + on-disk index storage path (when set) go in `init_options`. The `efm`
-- field is PER-FILETYPE (core.catalog.efm_groups): a chosen php-cs-fixer / phpstan lands on `php`,
-- never smeared across filetypes. intelephense formats PHP natively, so when an efm formatter is
-- active the client's formatting capability is switched off (catalog.lsp_on_attach) to avoid
-- double-formatting.
--
---@module "lvim-lang.servers.intelephense"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local php_dap = require("lvim-lang.providers.php.dap")

--- The PHP provider's config block.
---@return table
local function opts()
    return config.providers.php or {}
end

--- The intelephense server catalog entry (settings / init_options), from
--- config.providers.php.lsp.servers.intelephense.
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.intelephense) or {}
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
        --- Built fresh per root so the intelephense binary tracks the project's toolchain (version
        --- manager / PATH).
        ---@return table
        config = function()
            local so = server_opts()
            local o = opts()
            local intelephense = toolchain.resolve("php", "intelephense", current_root()) or "intelephense"
            local cfg = {
                cmd = so.cmd or { intelephense, "--stdio" },
                filetypes = { "php" },
                capabilities = capabilities(),
                -- Hand formatting to efm when a formatter is active for the buffer (else intelephense
                -- formats). Composes any user server on_attach.
                on_attach = catalog.lsp_on_attach("php", "intelephense"),
            }
            -- Only send settings when non-empty (an empty Lua table encodes as a JSON array []).
            if so.settings and next(so.settings) then
                cfg.settings = so.settings
            end
            -- init_options: the user's, plus the premium licence key + index storage path when set.
            local init = vim.deepcopy(so.init_options or {})
            if o.licence_key and o.licence_key ~= "" then
                init.licenceKey = o.licence_key
            end
            if o.storage_path and o.storage_path ~= "" then
                init.storagePath = o.storage_path
            end
            if next(init) then
                cfg.init_options = init
            end
            return cfg
        end,
    },
}
