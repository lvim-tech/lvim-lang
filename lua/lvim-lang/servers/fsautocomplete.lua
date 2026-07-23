-- lvim-lang.servers.fsautocomplete: the lvim-ls server-config module for FsAutoComplete (the F# LSP).
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the F# provider's LSP
-- catalog registers through core.lsp (register_catalog fans the chosen servers out). lvim-lang does
-- NOT own the LSP lifecycle — this module only DESCRIBES the server; the canonical lvim-ls bootstrap
-- starts and manages the client.
--
-- `lsp.config` is a FUNCTION (a seam lvim-ls supports): evaluated fresh per project root, so the
-- fsautocomplete binary is resolved per root through core.toolchain (a version-managed SDK and the
-- PATH one both start correctly). FsAutoComplete is configured through LSP `settings` under the
-- `FSharp` namespace, forwarded as-is when non-empty. It formats F# NATIVELY through its bundled
-- Fantomas, so the default efm formatter is `false` (efm is engaged only if the user opts one in).
--
---@module "lvim-lang.servers.fsautocomplete"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local fsharp_dap = require("lvim-lang.providers.fsharp.dap")

--- The F# provider's config block.
---@return table
local function opts()
    return config.providers.fsharp or {}
end

--- The fsautocomplete server catalog entry (settings / cmd override), from
--- config.providers.fsharp.lsp.servers.fsautocomplete.
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.fsautocomplete) or {}
end

--- Whether a directory entry name is an F# project-root marker (a `.sln`/`.fsproj` glob, the paket
--- manifest, or `.git`).
---@param name string
---@return boolean
local function root_matcher(name)
    return name:match("%.sln$") ~= nil
        or name:match("%.fsproj$") ~= nil
        or name == "paket.dependencies"
        or name == ".git"
end

--- Resolve the project root for the current buffer using F#'s root markers (function matcher).
---@return string
local function current_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, root_matcher) or vim.fs.dirname(name)
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
    -- netcoredbg adapter + base F# debug configurations (auto-registered with lvim-dap on attach).
    dap = fsharp_dap.spec(),
    -- Per-filetype formatter/linter routing (chosen tools only; empty when none selected).
    efm = catalog.efm_groups("fsharp"),
    lsp = {
        root_patterns = { ".fsproj", ".sln", "paket.dependencies", ".git" },
        --- Built fresh per root so the fsautocomplete binary tracks the project's SDK (version manager
        --- / PATH).
        ---@return table
        config = function()
            local so = server_opts()
            local fsac = toolchain.resolve("fsharp", "fsautocomplete", current_root()) or "fsautocomplete"
            -- FsAutoComplete speaks LSP over stdio by default. Fully overridable via config `cmd`.
            local cmd = so.cmd or { fsac }
            local cfg = {
                cmd = cmd,
                filetypes = { "fsharp" },
                capabilities = capabilities(),
                -- Hand formatting to efm when a formatter is active for the buffer's ft (else
                -- FsAutoComplete formats via bundled Fantomas). Composes any user server on_attach.
                on_attach = catalog.lsp_on_attach("fsharp", "fsautocomplete"),
            }
            -- Only send settings when non-empty: an empty Lua table encodes as a JSON ARRAY ([]), which
            -- servers reject. FsAutoComplete's configuration lives under the `FSharp` namespace.
            if so.settings and next(so.settings) then
                cfg.settings = so.settings
            end
            return cfg
        end,
    },
}
