-- lvim-lang.servers.zls: the lvim-ls server-config module for zls (the Zig language server).
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the Zig provider's LSP
-- catalog registers through core.lsp (register_catalog fans the chosen servers out). lvim-lang does
-- NOT own the LSP lifecycle — this module only DESCRIBES the server; the canonical lvim-ls bootstrap
-- starts and manages the client.
--
-- `lsp.config` is a FUNCTION (a seam lvim-ls supports): evaluated fresh per project root, so the
-- `zls` binary is resolved per root through core.toolchain (an explicit path / mason / PATH). zls
-- needs to find the `zig` binary to resolve the standard library, build on save, and format; when a
-- project pins Zig through mise / asdf, that per-root `zig` is passed to zls via its `zig_exe_path`
-- setting so it uses the SAME toolchain the tasks do. zls formats natively (it shells out to `zig
-- fmt`); the `efm` field is per-filetype (core.catalog.efm_groups) — a chosen `zig fmt` formatter
-- lands on `zig` only, and disables zls' own formatting through the shared on_attach.
--
---@module "lvim-lang.servers.zls"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local zig_dap = require("lvim-lang.providers.zig.dap")

--- The Zig provider's config block.
---@return table
local function opts()
    return config.providers.zig or {}
end

--- The zls server catalog entry (settings / init_options), from config.providers.zig.lsp.servers.zls.
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.zls) or {}
end

--- Resolve the project root for the current buffer using Zig's root markers.
---@return string
local function current_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "build.zig", "build.zig.zon", ".git" }) or vim.fs.dirname(name)
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
    -- lldb-dap + codelldb adapters + base Zig debug configurations (auto-registered with lvim-dap
    -- on attach).
    dap = zig_dap.spec(),
    -- Per-filetype formatter routing (chosen tools only; empty when none selected — zls formats
    -- natively via `zig fmt` by default).
    efm = catalog.efm_groups("zig"),
    lsp = {
        root_patterns = { "build.zig", "build.zig.zon", ".git" },
        --- Built fresh per root so the zls binary AND the zig it drives track the project's toolchain.
        ---@return table
        config = function()
            local root = current_root()
            local so = server_opts()
            local zls = toolchain.resolve("zig", "zls", root) or "zls"
            local cfg = {
                cmd = { zls },
                filetypes = { "zig" },
                capabilities = capabilities(),
                -- Hand formatting to efm when a `zig fmt` formatter is active for the buffer (else zls
                -- formats — natively via `zig fmt`). Composes any user server on_attach.
                on_attach = catalog.lsp_on_attach("zig", "zls"),
            }
            -- Point zls at the SAME zig the tasks resolve (a project-pinned toolchain), unless the user
            -- already set zig_exe_path explicitly. zls needs it to resolve std / build / format.
            local settings = vim.deepcopy(so.settings) or {}
            settings.zls = settings.zls or {}
            if settings.zls.zig_exe_path == nil then
                local zig = toolchain.resolve("zig", "zig", root)
                if zig then
                    settings.zls.zig_exe_path = zig
                end
            end
            -- Only send settings / init_options when non-empty: an empty Lua table encodes as a JSON
            -- ARRAY ([]), which servers reject.
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
