-- lvim-lang.servers.clangd: the lvim-ls server-config module for clangd (the C/C++ language server).
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the C/C++ provider's LSP
-- catalog registers through core.lsp (register_catalog fans the chosen servers out). lvim-lang does
-- NOT own the LSP lifecycle — this module only DESCRIBES the server; the canonical lvim-ls bootstrap
-- starts and manages the client.
--
-- clangd is configured through COMMAND-LINE FLAGS, not workspace settings: the `cmd` is the resolved
-- clangd binary followed by the catalog's `flags` (`--background-index --clang-tidy …`). `lsp.config`
-- is a FUNCTION (a seam lvim-ls supports): evaluated fresh per project root so the binary is resolved
-- per root through core.toolchain (an explicit path / mason / PATH). The `efm` field is per-filetype
-- (core.catalog.efm_groups): a chosen clang-format / clang-tidy lands on its own filetype only.
--
---@module "lvim-lang.servers.clangd"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local cpp_dap = require("lvim-lang.providers.cpp.dap")

--- The C/C++ provider's config block.
---@return table
local function opts()
    return config.providers.cpp or {}
end

--- The clangd server catalog entry (flags / init_options), from config.providers.cpp.lsp.servers.clangd.
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.clangd) or {}
end

--- Resolve the project root for the current buffer using clangd's root markers.
---@return string
local function current_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "compile_commands.json", "CMakeLists.txt", "Makefile", ".clangd", ".git" })
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
    -- CodeLLDB + cpptools adapters + base C/C++ debug configurations (auto-registered with lvim-dap
    -- on attach).
    dap = cpp_dap.spec(),
    -- Per-filetype formatter/linter routing (chosen tools only; empty when none selected — clangd
    -- formats + lints natively by default).
    efm = catalog.efm_groups("cpp"),
    lsp = {
        root_patterns = { "compile_commands.json", "CMakeLists.txt", "Makefile", ".clangd", ".git" },
        --- Built fresh per root so the clangd binary tracks the project's toolchain (explicit / mason / PATH).
        ---@return table
        config = function()
            local so = server_opts()
            local clangd = toolchain.resolve("cpp", "clangd", current_root()) or "clangd"
            -- clangd is configured via flags: the binary, then the catalog's flag list.
            local cmd = { clangd }
            vim.list_extend(cmd, so.flags or {})
            local cfg = {
                cmd = cmd,
                filetypes = { "c", "cpp", "objc", "objcpp" },
                capabilities = capabilities(),
                -- Hand formatting to efm when a formatter is active for the buffer's ft (else clangd
                -- formats — clang-format natively). Composes any user server on_attach.
                on_attach = catalog.lsp_on_attach("cpp", "clangd"),
            }
            -- Only send init_options when non-empty: an empty Lua table encodes as a JSON ARRAY ([]),
            -- which servers reject.
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
