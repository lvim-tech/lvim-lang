-- lvim-lang.servers.elixir-ls: the lvim-ls server-config module for elixir-ls (ElixirLS).
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the Elixir provider's LSP
-- catalog registers through core.lsp. lvim-lang does NOT own the LSP lifecycle — this module only
-- DESCRIBES the server; the canonical lvim-ls bootstrap starts and manages the client.
--
-- `lsp.config` is a FUNCTION (a seam lvim-ls supports): evaluated fresh per project root, so the
-- elixir-ls binary is resolved per root through core.toolchain (tracking a version-managed elixir).
-- elixir-ls reads its configuration from `settings` under the `elixirLS` key (workspace/
-- didChangeConfiguration) AND `init_options` (so it has the config at startup). It formats via
-- `mix format` and reports credo / dialyzer diagnostics natively, so `catalog.lsp_on_attach` yields
-- the buffer's formatting to efm ONLY when the user has selected an efm formatter for `elixir`. The
-- `dap` field carries the elixir-ls DEBUGGER adapter + base configurations (auto-registered with
-- lvim-dap on attach); `efm` is the per-filetype mix-format / credo routing when one is chosen.
--
---@module "lvim-lang.servers.elixir-ls"

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

--- The elixir-ls server catalog entry (settings / init_options).
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers["elixir-ls"]) or {}
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
        --- Built fresh per root so the elixir-ls binary tracks the project's elixir.
        ---@return table
        config = function()
            local so = server_opts()
            local bin = toolchain.resolve("elixir", "elixir-ls", current_root()) or "elixir-ls"
            local cfg = {
                cmd = { bin },
                filetypes = so.filetypes or { "elixir", "eelixir", "heex" },
                capabilities = capabilities(),
                -- Hand formatting to efm when a formatter is active for the buffer (else elixir-ls
                -- formats). Composes any user server on_attach.
                on_attach = catalog.lsp_on_attach("elixir", "elixir-ls"),
            }
            -- Only send non-empty tables (an empty Lua table encodes as a JSON array []). elixir-ls
            -- wants the `elixirLS` block as `settings` (pushed after init) AND `init_options`.
            if so.settings and next(so.settings) then
                cfg.settings = so.settings
            end
            local init = so.init_options or so.settings
            if init and next(init) then
                cfg.init_options = init
            end
            return cfg
        end,
    },
}
