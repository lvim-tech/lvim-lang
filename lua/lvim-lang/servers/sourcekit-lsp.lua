-- lvim-lang.servers.sourcekit-lsp: the lvim-ls server-config module for sourcekit-lsp (the Swift /
-- SourceKit language server). Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix
-- that the Swift provider's LSP catalog registers through core.lsp. lvim-lang does NOT own the LSP
-- lifecycle — this module only DESCRIBES the server; the canonical lvim-ls bootstrap starts and
-- manages the client.
--
-- sourcekit-lsp SHIPS WITH the Swift toolchain (beside `swift` in the same bin dir) — it is never a
-- mason package, exactly like dartls ships with the Dart SDK. `lsp.config` is a FUNCTION (a seam
-- lvim-ls supports): evaluated fresh per project root, so the sourcekit-lsp binary is resolved per
-- root through core.toolchain (a project-pinned toolchain in one package, the PATH toolchain in
-- another, both start correctly). The `efm` field is per-filetype (core.catalog.efm_groups) — the
-- chosen swiftformat / swiftlint lands on `swift` only; `on_attach` hands formatting to efm when a
-- formatter is active (so sourcekit-lsp and swiftformat do not both format the buffer).
--
---@module "lvim-lang.servers.sourcekit-lsp"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local swift_dap = require("lvim-lang.providers.swift.dap")

--- The Swift provider's config block.
---@return table
local function opts()
    return config.providers.swift or {}
end

--- The sourcekit-lsp server catalog entry (settings / init_options), from
--- config.providers.swift.lsp.servers["sourcekit-lsp"].
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers["sourcekit-lsp"]) or {}
end

--- Resolve the project root for the current buffer using SwiftPM's root markers.
---@return string
local function current_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "Package.swift", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The LSP client_capabilities fragment: lvim-cmp's when present (so sourcekit-lsp advertises the
--- completion features the engine needs), else the Neovim defaults.
---@return table
local function capabilities()
    local ok, cmp = pcall(require, "lvim-cmp")
    if ok and type(cmp.capabilities) == "function" then
        return cmp.capabilities()
    end
    return vim.lsp.protocol.make_client_capabilities()
end

return {
    -- lldb-dap / CodeLLDB adapters + base Swift debug configurations (auto-registered with lvim-dap
    -- on attach).
    dap = swift_dap.spec(),
    -- Per-filetype formatter/linter routing (chosen tools only; empty when none selected).
    efm = catalog.efm_groups("swift"),
    lsp = {
        root_patterns = { "Package.swift", ".git" },
        --- Built fresh per root so the sourcekit-lsp binary tracks the project's toolchain.
        ---@return table
        config = function()
            local so = server_opts()
            -- sourcekit-lsp ships with the toolchain; resolve it beside `swift` (or an explicit path / PATH).
            local skls = toolchain.resolve("swift", "sourcekit-lsp", current_root()) or "sourcekit-lsp"
            local cfg = {
                cmd = { skls },
                filetypes = { "swift" },
                capabilities = capabilities(),
                -- Hand formatting to efm when a formatter (swiftformat) is active for `swift`; else
                -- sourcekit-lsp formats. Composes any user server on_attach.
                on_attach = catalog.lsp_on_attach("swift", "sourcekit-lsp"),
            }
            -- Only send non-empty tables: an empty Lua table encodes as a JSON ARRAY ([]), which
            -- servers reject.
            if so.init_options and next(so.init_options) then
                cfg.init_options = so.init_options
            end
            if so.settings and next(so.settings) then
                cfg.settings = so.settings
            end
            return cfg
        end,
    },
}
