-- lvim-lang.servers.haskell-language-server: the lvim-ls server-config module for HLS.
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the Haskell provider's LSP
-- catalog registers through core.lsp (register_catalog fans the chosen servers out). lvim-lang does
-- NOT own the LSP lifecycle — this module only DESCRIBES the server; the canonical lvim-ls bootstrap
-- starts and manages the client.
--
-- The mason `haskell-language-server` package installs a `haskell-language-server-wrapper` binary that
-- selects the correct HLS build for the project's GHC; the server is launched as `<wrapper> --lsp`.
-- `lsp.config` is a FUNCTION (a seam lvim-ls supports): evaluated fresh per project root, so the HLS
-- binary is resolved per root through core.toolchain (GHCup honours the active toolchain). HLS is
-- configured through workspace `settings.haskell`. The `efm` field is per-filetype
-- (core.catalog.efm_groups): a chosen fourmolu / ormolu / hlint lands on its own filetype only.
--
---@module "lvim-lang.servers.haskell-language-server"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local haskell_dap = require("lvim-lang.providers.haskell.dap")

--- The Haskell provider's config block.
---@return table
local function opts()
    return config.providers.haskell or {}
end

--- The HLS server catalog entry (settings / init_options).
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers["haskell-language-server"]) or {}
end

--- Resolve the project root for the current buffer using Haskell's root markers.
---@return string
local function current_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "stack.yaml", "cabal.project", "package.yaml", ".git" }) or vim.fs.dirname(name)
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
    -- haskell-debug-adapter (phoityne) adapter + base Haskell debug configuration (auto-registered
    -- with lvim-dap on attach).
    dap = haskell_dap.spec(),
    -- Per-filetype formatter/linter routing (chosen tools only; empty when none selected — HLS
    -- formats + lints natively by default).
    efm = catalog.efm_groups("haskell"),
    lsp = {
        root_patterns = { "stack.yaml", "cabal.project", "package.yaml", ".git" },
        --- Built fresh per root so the HLS binary tracks the project's toolchain (the wrapper selects
        --- the right HLS for the GHC in scope).
        ---@return table
        config = function()
            local so = server_opts()
            local hls = toolchain.resolve("haskell", "haskell-language-server", current_root())
                or "haskell-language-server-wrapper"
            local cfg = {
                cmd = { hls, "--lsp" },
                filetypes = so.filetypes or { "haskell", "lhaskell" },
                capabilities = capabilities(),
                on_attach = catalog.lsp_on_attach("haskell", "haskell-language-server"),
            }
            -- Only send non-empty tables: an empty Lua table encodes as a JSON ARRAY ([]), which
            -- servers reject.
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
