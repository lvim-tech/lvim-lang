-- lvim-lang.servers.erlang-ls: the lvim-ls server-config module for erlang_ls (the erlang-ls LSP).
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the Erlang provider's LSP
-- catalog registers through core.lsp. lvim-lang does NOT own the LSP lifecycle — this module only
-- DESCRIBES the server; the canonical lvim-ls bootstrap starts and manages the client.
--
-- erlang_ls is configured through an `erlang_ls.config` file at the project root (its own config
-- format), not through the protocol, so no `settings` are pushed by default. The binary is resolved
-- per root through the toolchain (an explicit path → the mason bin → PATH). erlang_ls does not format
-- Erlang, so `catalog.lsp_on_attach` hands formatting to efm whenever the erlfmt formatter is active
-- for `erlang` (the default). The `efm` field is the per-filetype erlfmt routing. There is NO `dap`
-- field: Erlang has no reliable mason debug adapter.
--
---@module "lvim-lang.servers.erlang-ls"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")

--- Erlang's root markers (rebar.config / erlang.mk, then `.git`).
---@type string[]
local ROOT_PATTERNS = { "rebar.config", "erlang.mk", ".git" }

--- The Erlang provider's config block.
---@return table
local function opts()
    return config.providers.erlang or {}
end

--- The erlang-ls server catalog entry (settings).
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers["erlang-ls"]) or {}
end

--- Resolve the project root for the current buffer using Erlang's root markers.
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
    -- Per-filetype formatter/linter routing (chosen efm tools only; erlfmt is the default formatter).
    efm = catalog.efm_groups("erlang"),
    lsp = {
        root_patterns = ROOT_PATTERNS,
        --- Built fresh per root so the erlang_ls binary tracks the project's resolution.
        ---@return table
        config = function()
            local so = server_opts()
            local bin = toolchain.resolve("erlang", "erlang_ls", current_root()) or "erlang_ls"
            local cfg = {
                cmd = { bin },
                filetypes = so.filetypes or { "erlang" },
                capabilities = capabilities(),
                -- Hand formatting to efm when a formatter is active for the buffer (erlfmt by default).
                -- Composes any user server on_attach.
                on_attach = catalog.lsp_on_attach("erlang", "erlang-ls"),
            }
            -- Only send a non-empty settings table (an empty Lua table encodes as a JSON array []).
            if so.settings and next(so.settings) then
                cfg.settings = so.settings
            end
            return cfg
        end,
    },
}
