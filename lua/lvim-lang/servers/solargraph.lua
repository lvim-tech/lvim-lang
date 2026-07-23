-- lvim-lang.servers.solargraph: the lvim-ls server-config module for solargraph (the alternative
-- Ruby language server). Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that
-- the Ruby provider's LSP catalog registers through core.lsp — only when the user selects it
-- (`lsp.server = "solargraph"`). lvim-lang does NOT own the LSP lifecycle — this module only
-- DESCRIBES the server; the canonical lvim-ls bootstrap starts and manages the client.
--
-- solargraph runs as `solargraph stdio` and reads its config from `settings.solargraph`. It formats +
-- diagnoses natively (via rubocop when `useBundler` finds it in the bundle), so `catalog.lsp_on_attach`
-- yields formatting to efm only when the user has selected an efm formatter for `ruby`. The binary is
-- resolved per root through the toolchain (a project binstub / the selected ruby's bin / mason / PATH).
-- The `dap` / `efm` fields mirror ruby-lsp so debugging + efm routing work when solargraph is the
-- chosen server.
--
---@module "lvim-lang.servers.solargraph"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local ruby_dap = require("lvim-lang.providers.ruby.dap")

--- Ruby's root markers (Gemfile / Rakefile / .ruby-version, then `.git`).
---@type string[]
local ROOT_PATTERNS = { "Gemfile", "Rakefile", ".ruby-version", ".git" }

--- The Ruby provider's config block.
---@return table
local function opts()
    return config.providers.ruby or {}
end

--- The solargraph server catalog entry (settings).
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.solargraph) or {}
end

--- Resolve the project root for the current buffer using Ruby's root markers.
---@return string
local function current_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, ROOT_PATTERNS) or vim.fs.dirname(name)
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
    -- rdbg adapter + base ruby debug configurations (auto-registered with lvim-dap on attach).
    dap = ruby_dap.spec(),
    -- Per-filetype formatter/linter routing (chosen efm tools only; empty when none selected).
    efm = catalog.efm_groups("ruby"),
    lsp = {
        root_patterns = ROOT_PATTERNS,
        --- Built fresh per root so the solargraph binary tracks the project's ruby / bundle.
        ---@return table
        config = function()
            local so = server_opts()
            local bin = toolchain.resolve("ruby", "solargraph", current_root()) or "solargraph"
            local cfg = {
                cmd = { bin, "stdio" },
                filetypes = so.filetypes or { "ruby" },
                capabilities = capabilities(),
                on_attach = catalog.lsp_on_attach("ruby", "solargraph"),
            }
            -- Only send non-empty settings (an empty Lua table encodes as a JSON array []).
            if so.settings and next(so.settings) then
                cfg.settings = so.settings
            end
            return cfg
        end,
    },
}
