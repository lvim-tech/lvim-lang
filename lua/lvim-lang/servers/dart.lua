-- lvim-lang.servers.dart: the lvim-ls server-config module for dartls (the Dart analysis server).
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the Dart provider
-- registers through core.lsp. lvim-lang does NOT own the LSP lifecycle — this module only
-- DESCRIBES the server; the canonical lvim-ls bootstrap starts and manages the client.
--
-- `lsp.config` is a FUNCTION (a seam lvim-ls supports): it is evaluated fresh for each new
-- project root, so the `dart` binary is resolved per root through core.toolchain — an
-- FVM-pinned SDK in one project and the PATH SDK in another both start correctly.
--
---@module "lvim-lang.servers.dart"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local decorations = require("lvim-lang.core.decorations")
local labels_spec = require("lvim-lang.providers.dart.labels")
local outline = require("lvim-lang.providers.dart.outline")
local dart_dap = require("lvim-lang.providers.dart.dap")

-- Register the dynamic device-aware dap config provider once, when the server config loads (i.e.
-- on the first dartls attach — by then lvim-dap is available if debugging is in use).
dart_dap.register_provider()

--- The Dart provider's config block.
---@return table
local function opts()
    return config.providers.dart or {}
end

--- The dartls server catalog entry (settings / init_options), from config.providers.dart.lsp.servers.dart.
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.dart) or {}
end

--- Resolve the project root for the current buffer using dartls' root markers.
---@return string
local function current_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "pubspec.yaml", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The LSP client_capabilities fragment: lvim-cmp's when present (so dartls advertises the
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
    -- Auto-registered with lvim-dap by lvim-ls (adapters + base configurations).
    dap = dart_dap.spec(),
    lsp = {
        root_patterns = { "pubspec.yaml", ".git" },
        --- Built fresh per root so the dart binary tracks the project's SDK (FVM/PATH).
        ---@return table
        config = function()
            local o = opts()
            local so = server_opts()
            local dart = toolchain.resolve("dart", "dart", current_root()) or "dart"
            -- closingLabels must be requested in init_options for dartls to SEND the
            -- notifications at all; the decoration engine then gates their rendering (so the
            -- runtime toggle just shows/hides the cached extmarks). Only request them when
            -- decorations are globally enabled.
            local deco_on = not (o.decorations and o.decorations.closing_labels == false)
                and not (config.decorations and config.decorations.enabled == false)
            -- flutterOutline drives the Flutter Outline source for the outline panel.
            local outline_on = o.outline ~= false
            local init = vim.tbl_extend("force", so.init_options or {}, {
                closingLabels = deco_on,
                flutterOutline = outline_on,
            })
            return {
                cmd = { dart, "language-server", "--protocol=lsp" },
                filetypes = { "dart" },
                capabilities = capabilities(),
                init_options = init,
                settings = { dart = so.settings or {} },
                handlers = {
                    ["dart/textDocument/publishClosingLabels"] = decorations.handler(labels_spec),
                    ["dart/textDocument/publishFlutterOutline"] = outline.handler(),
                },
            }
        end,
    },
}
