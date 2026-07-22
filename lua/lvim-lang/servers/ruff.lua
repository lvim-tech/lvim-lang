-- lvim-lang.servers.ruff: the lvim-ls server-config module for the ruff language server.
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the Python provider's
-- LSP catalog registers through core.lsp. lvim-lang does NOT own the LSP lifecycle — this module
-- only DESCRIBES the server; the canonical lvim-ls bootstrap starts and manages the client.
--
-- ruff runs as `ruff server` and owns lint diagnostics, formatting and organize-imports for Python;
-- it attaches ALONGSIDE basedpyright (the types server). To avoid overlap its `on_attach` (in the
-- provider catalog) turns OFF its hover capability so basedpyright owns hover. ruff's own settings
-- go under `init_options.settings` (not `settings`). The binary is resolved per root through the
-- venv-aware toolchain, so a project-local ruff wins over the shared mason copy. No `dap` / `efm`
-- here — those ride on the PRIMARY server (basedpyright).
--
---@module "lvim-lang.servers.ruff"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")

--- The Python provider's config block.
---@return table
local function opts()
    return config.providers.python or {}
end

--- The ruff server catalog entry (init_options).
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.ruff) or {}
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
    lsp = {
        root_patterns = { "pyproject.toml", "ruff.toml", ".ruff.toml", "setup.cfg", ".git" },
        --- Built fresh per root so the ruff binary tracks the project's environment.
        ---@return table
        config = function()
            local so = server_opts()
            local ruff = toolchain.resolve("python", "ruff", current_root()) or "ruff"
            local cfg = {
                cmd = { ruff, "server" },
                filetypes = { "python" },
                capabilities = capabilities(),
                on_attach = catalog.lsp_on_attach("python", "ruff"),
            }
            -- Only send non-empty tables: an empty Lua table encodes as a JSON ARRAY ([]), which the
            -- server rejects. ruff reads its config from init_options.settings.
            if so.init_options and next(so.init_options) then
                cfg.init_options = so.init_options
            end
            return cfg
        end,
    },
}
