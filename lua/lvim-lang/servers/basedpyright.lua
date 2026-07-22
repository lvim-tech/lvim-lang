-- lvim-lang.servers.basedpyright: the lvim-ls server-config module for basedpyright.
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the Python provider's
-- LSP catalog registers through core.lsp. lvim-lang does NOT own the LSP lifecycle — this module
-- only DESCRIBES the server; the canonical lvim-ls bootstrap starts and manages the client.
--
-- `lsp.config` is a FUNCTION (a seam lvim-ls supports): evaluated fresh per project root, so BOTH
-- the `basedpyright-langserver` binary AND `python.pythonPath` are resolved per root through the
-- venv-aware toolchain — the language server therefore analyses the code against the SAME
-- interpreter the tests / debugger run under, and imports resolve correctly. basedpyright is the
-- PRIMARY server: it carries the `dap` field (debugpy) and the per-filetype `efm` groups; ruff (the
-- companion) yields formatting to nobody here — it formats itself, and basedpyright's own formatting
-- is switched off in its `on_attach` (set in the provider catalog).
--
---@module "lvim-lang.servers.basedpyright"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local python_dap = require("lvim-lang.providers.python.dap")

--- The Python provider's config block.
---@return table
local function opts()
    return config.providers.python or {}
end

--- The basedpyright server catalog entry (settings / init_options).
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.basedpyright) or {}
end

--- Resolve the project root for the current buffer using Python's root markers.
---@return string
local function current_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", "Pipfile", ".git" })
            or vim.fs.dirname(name)
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
    -- debugpy adapter + base python debug configurations (auto-registered with lvim-dap on attach).
    dap = python_dap.spec(),
    -- Per-filetype formatter/linter routing (chosen efm tools only; empty when none selected).
    efm = catalog.efm_groups("python"),
    lsp = {
        root_patterns = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", "Pipfile", ".git" },
        --- Built fresh per root: the server binary AND the analysed interpreter track the project venv.
        ---@return table
        config = function()
            local root = current_root()
            local so = server_opts()
            local server = toolchain.resolve("python", "basedpyright", root) or "basedpyright-langserver"
            local cfg = {
                cmd = { server, "--stdio" },
                filetypes = { "python" },
                capabilities = capabilities(),
                on_attach = catalog.lsp_on_attach("python", "basedpyright"),
            }
            -- Point basedpyright at the resolved interpreter so imports resolve against the project's
            -- environment (the whole reason the toolchain is venv-aware). Merge onto the catalog
            -- settings without mutating the shared config table.
            local settings = vim.deepcopy(so.settings or {})
            local py = toolchain.resolve("python", "python", root)
            if py then
                settings.python = settings.python or {}
                settings.python.pythonPath = py
            end
            -- Only send non-empty tables: an empty Lua table encodes as a JSON ARRAY ([]), which the
            -- server rejects.
            if next(settings) then
                cfg.settings = settings
            end
            if so.init_options and next(so.init_options) then
                cfg.init_options = so.init_options
            end
            return cfg
        end,
    },
}
