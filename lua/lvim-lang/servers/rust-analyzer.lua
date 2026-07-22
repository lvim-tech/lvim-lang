-- lvim-lang.servers.rust-analyzer: the lvim-ls server-config module for rust-analyzer.
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the Rust provider's LSP
-- catalog registers through core.lsp (register_catalog fans the chosen servers out). lvim-lang does
-- NOT own the LSP lifecycle — this module only DESCRIBES the server; the canonical lvim-ls bootstrap
-- starts and manages the client.
--
-- `lsp.config` is a FUNCTION (a seam lvim-ls supports): evaluated fresh per project root, so the
-- rust-analyzer binary is resolved per root through core.toolchain (rustup honours a project's
-- rust-toolchain.toml). The RA config is passed BOTH as `settings` (workspace/didChangeConfiguration)
-- AND as `init_options` (so RA has it at startup, before the first config push). The `efm` field is
-- per-filetype (core.catalog.efm_groups) — a chosen rustfmt/bacon lands on `rust` only.
--
---@module "lvim-lang.servers.rust-analyzer"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local rust_dap = require("lvim-lang.providers.rust.dap")

--- The Rust provider's config block.
---@return table
local function opts()
    return config.providers.rust or {}
end

--- The rust-analyzer server catalog entry (settings / init_options).
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers["rust-analyzer"]) or {}
end

--- Resolve the project root for the current buffer using Cargo's root markers.
---@return string
local function current_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "Cargo.toml", "Cargo.lock", ".git" }) or vim.fs.dirname(name)
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
    -- CodeLLDB adapter + base rust debug configurations (auto-registered with lvim-dap on attach).
    dap = rust_dap.spec(),
    -- Per-filetype formatter/linter routing (chosen tools only; empty when none selected).
    efm = catalog.efm_groups("rust"),
    lsp = {
        root_patterns = { "Cargo.toml", "Cargo.lock", ".git" },
        --- Built fresh per root so the rust-analyzer binary tracks the project's toolchain.
        ---@return table
        config = function()
            local so = server_opts()
            local ra = toolchain.resolve("rust", "rust-analyzer", current_root()) or "rust-analyzer"
            local cfg = {
                cmd = { ra },
                filetypes = { "rust" },
                capabilities = capabilities(),
                on_attach = catalog.lsp_on_attach("rust", "rust-analyzer"),
            }
            -- Only send non-empty tables: an empty Lua table encodes as a JSON ARRAY ([]), which
            -- servers reject. The catalog stores RA's config nested under the `rust-analyzer` key; RA
            -- wants it as `settings` (pushed after init) AND `init_options` (available at startup).
            if so.settings and next(so.settings) then
                cfg.settings = so.settings
            end
            local init = so.init_options or (so.settings and so.settings["rust-analyzer"])
            if init and next(init) then
                cfg.init_options = init
            end
            return cfg
        end,
    },
}
