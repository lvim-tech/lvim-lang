-- lvim-lang.servers.lexical: the lvim-ls server-config module for lexical (the Lexical language
-- server, an alternative to elixir-ls). Loaded by the lvim-ls manager via the "lvim-lang.servers" dir
-- prefix when the Elixir provider's LSP catalog selects `lexical` (lsp.server = "lexical"). lvim-lang
-- does NOT own the LSP lifecycle — this module only DESCRIBES the server.
--
-- lexical is a single-binary server (`lexical`) that formats + diagnoses natively, so
-- `catalog.lsp_on_attach` yields formatting to efm only when an efm formatter is selected for
-- `elixir`. The binary is resolved per root through core.toolchain (mason → PATH). The `dap` field
-- carries the elixir-ls debugger adapter so per-cursor debugging works even with lexical as the LSP.
--
---@module "lvim-lang.servers.lexical"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local elixir_dap = require("lvim-lang.providers.elixir.dap")

--- Elixir's root markers (mix.exs, then `.git`).
---@type string[]
local ROOT_PATTERNS = { "mix.exs", ".git" }

--- The Elixir provider's config block.
---@return table
local function opts()
    return config.providers.elixir or {}
end

--- The lexical server catalog entry (settings).
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.lexical) or {}
end

--- Resolve the project root for the current buffer using Elixir's root markers.
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
    -- elixir-ls debugger adapter + base elixir debug configurations (auto-registered on attach).
    dap = elixir_dap.spec(),
    -- Per-filetype formatter/linter routing (chosen efm tools only; empty when none selected).
    efm = catalog.efm_groups("elixir"),
    lsp = {
        root_patterns = ROOT_PATTERNS,
        --- Built fresh per root so the lexical binary tracks the resolved install.
        ---@return table
        config = function()
            local so = server_opts()
            local bin = toolchain.resolve("elixir", "lexical", current_root()) or "lexical"
            local cfg = {
                cmd = { bin },
                filetypes = so.filetypes or { "elixir", "eelixir", "heex" },
                capabilities = capabilities(),
                on_attach = catalog.lsp_on_attach("elixir", "lexical"),
            }
            if so.settings and next(so.settings) then
                cfg.settings = so.settings
            end
            return cfg
        end,
    },
}
