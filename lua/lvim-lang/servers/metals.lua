-- lvim-lang.servers.metals: the lvim-ls server-config module for metals (the Scala language server).
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the Scala provider's LSP
-- catalog registers through core.lsp. lvim-lang does NOT own the LSP lifecycle — this module only
-- DESCRIBES the server; the canonical lvim-ls bootstrap starts and manages the client.
--
-- `lsp.config` is a FUNCTION (a seam lvim-ls supports): evaluated fresh per project root, so the
-- `metals` binary is resolved per root through core.toolchain (a version-managed toolchain in one
-- project and the PATH one in another both start correctly). metals is a JVM program launched through
-- the mason wrapper script (which locates a `java` itself) — the Java-runtime requirement is surfaced
-- by the provider, not forced here. metals MANAGES its own build server (Bloop over BSP) — it imports
-- the sbt / mill / bloop build and drives compilation, diagnostics, code lenses AND debugging — so
-- there is no BSP client to configure. The `efm` field is PER-FILETYPE (core.catalog.efm_groups):
-- scalafmt (opt-in) lands on `scala`; when active, metals' own formatting is handed to efm on attach
-- so the two never both format. Debugging rides on the `dap` field (providers.scala.dap), a metals
-- `debug-adapter-start` server adapter auto-registered with lvim-dap on attach.
--
---@module "lvim-lang.servers.metals"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local scala_dap = require("lvim-lang.providers.scala.dap")

--- Scala's root markers (build scripts, then `.git`).
---@type string[]
local ROOT_PATTERNS = { "build.sbt", "build.sc", ".git" }

--- The Scala provider's config block.
---@return table
local function opts()
    return config.providers.scala or {}
end

--- The metals server catalog entry (settings / init_options), from
--- config.providers.scala.lsp.servers.metals.
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.metals) or {}
end

--- Resolve the project root for the current buffer using Scala's root markers.
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
    -- metals debug adapter + base scala debug configurations (auto-registered with lvim-dap on attach).
    dap = scala_dap.spec(),
    -- Per-filetype formatter/linter routing (chosen efm tools only; empty when none selected).
    efm = catalog.efm_groups("scala"),
    lsp = {
        root_patterns = ROOT_PATTERNS,
        --- Built fresh per root so the metals binary tracks the project's toolchain (version manager / PATH).
        ---@return table
        config = function()
            local so = server_opts()
            local metals = toolchain.resolve("scala", "metals", current_root()) or "metals"
            local cfg = {
                cmd = { metals },
                filetypes = { "scala", "sbt" },
                capabilities = capabilities(),
                -- Hand formatting to efm when a formatter is active for the buffer (scalafmt, opt-in),
                -- else metals formats. Composes any user server on_attach.
                on_attach = catalog.lsp_on_attach("scala", "metals"),
            }
            -- metals reads its user settings from the `metals` key of the didChangeConfiguration
            -- payload — which lvim-ls sends from `settings`. Only send when non-empty (an empty Lua
            -- table encodes as a JSON array []).
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
