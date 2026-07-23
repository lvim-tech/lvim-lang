-- lvim-lang.servers.ruby-lsp: the lvim-ls server-config module for ruby-lsp (Shopify's Ruby LSP).
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the Ruby provider's LSP
-- catalog registers through core.lsp. lvim-lang does NOT own the LSP lifecycle — this module only
-- DESCRIBES the server; the canonical lvim-ls bootstrap starts and manages the client.
--
-- ruby-lsp reads its configuration from `init_options` (formatter / linters / enabledFeatures) — the
-- catalog block is passed through verbatim. It integrates rubocop for formatting + diagnostics
-- itself when rubocop is in the project bundle, so `catalog.lsp_on_attach` yields the buffer's
-- formatting to efm ONLY when the user has selected an efm formatter for `ruby` (otherwise ruby-lsp
-- keeps formatting). The binary is resolved per root through the toolchain (a project binstub / the
-- selected ruby's bin / mason / PATH), so a project-local ruby-lsp wins over the shared mason copy.
-- The `dap` field carries the rdbg adapter + base configurations (auto-registered with lvim-dap on
-- attach); `efm` is the per-filetype rubocop / standardrb routing when one is chosen.
--
---@module "lvim-lang.servers.ruby-lsp"

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

--- The ruby-lsp server catalog entry (init_options).
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers["ruby-lsp"]) or {}
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
        --- Built fresh per root so the ruby-lsp binary tracks the project's ruby / bundle.
        ---@return table
        config = function()
            local so = server_opts()
            local bin = toolchain.resolve("ruby", "ruby-lsp", current_root()) or "ruby-lsp"
            local cfg = {
                cmd = { bin },
                filetypes = so.filetypes or { "ruby", "eruby" },
                capabilities = capabilities(),
                -- Hand formatting to efm when a formatter is active for the buffer (else ruby-lsp
                -- formats). Composes any user server on_attach.
                on_attach = catalog.lsp_on_attach("ruby", "ruby-lsp"),
            }
            -- ruby-lsp reads its options from init_options. Only send a non-empty table (an empty
            -- Lua table encodes as a JSON array []).
            if so.init_options and next(so.init_options) then
                cfg.init_options = so.init_options
            end
            return cfg
        end,
    },
}
