-- lvim-lang.servers.omnisharp: the lvim-ls server-config module for OmniSharp (the default C# LSP).
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the C# provider's LSP
-- catalog registers through core.lsp (register_catalog fans the chosen servers out). lvim-lang does
-- NOT own the LSP lifecycle — this module only DESCRIBES the server; the canonical lvim-ls bootstrap
-- starts and manages the client.
--
-- `lsp.config` is a FUNCTION (a seam lvim-ls supports): evaluated fresh per project root, so the
-- OmniSharp binary is resolved per root through core.toolchain (a version-managed SDK and the PATH
-- one both start correctly). OmniSharp is configured through CLI `key=value` OPTIONS (not LSP
-- settings), so the catalog `options` are appended to the launch command; `--hostPID` ties the
-- server's lifetime to Neovim's. Raw LSP `settings` are still forwarded when non-empty.
--
---@module "lvim-lang.servers.omnisharp"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local csharp_dap = require("lvim-lang.providers.csharp.dap")

--- The C# provider's config block.
---@return table
local function opts()
    return config.providers.csharp or {}
end

--- The OmniSharp server catalog entry (options / settings), from
--- config.providers.csharp.lsp.servers.omnisharp.
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.omnisharp) or {}
end

--- Whether a directory entry name is a C# project-root marker (a `.sln`/`.csproj` glob, or `.git`).
---@param name string
---@return boolean
local function root_matcher(name)
    return name:match("%.sln$") ~= nil or name:match("%.csproj$") ~= nil or name == ".git"
end

--- Resolve the project root for the current buffer using C#'s root markers (function matcher).
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
    -- netcoredbg adapter + base C# debug configurations (auto-registered with lvim-dap on attach).
    dap = csharp_dap.spec(),
    -- Per-filetype formatter/linter routing (chosen tools only; empty when none selected).
    efm = catalog.efm_groups("csharp"),
    lsp = {
        root_patterns = { ".sln", ".csproj", ".git" },
        --- Built fresh per root so the OmniSharp binary tracks the project's SDK (version manager / PATH).
        ---@return table
        config = function()
            local so = server_opts()
            local omnisharp = toolchain.resolve("csharp", "OmniSharp", current_root()) or "OmniSharp"
            -- `OmniSharp -lsp`: the language-server-over-stdio mode. --hostPID lets OmniSharp exit when
            -- Neovim does; --encoding pins UTF-8. Fully overridable via config `cmd`.
            local cmd = so.cmd or { omnisharp, "-lsp", "--encoding", "utf-8", "--hostPID", tostring(vim.fn.getpid()) }
            if not so.cmd then
                -- Append OmniSharp's CLI `key=value` options (its real configuration surface).
                local options = so.options or {}
                local keys = vim.tbl_keys(options)
                table.sort(keys)
                for _, k in ipairs(keys) do
                    cmd[#cmd + 1] = k .. "=" .. tostring(options[k])
                end
            end
            local cfg = {
                cmd = cmd,
                filetypes = { "cs" },
                capabilities = capabilities(),
                -- Hand formatting to efm when a formatter is active for the buffer's ft (else OmniSharp
                -- formats). Composes any user server on_attach.
                on_attach = catalog.lsp_on_attach("csharp", "omnisharp"),
            }
            -- Only send settings when non-empty: an empty Lua table encodes as a JSON ARRAY ([]), which
            -- servers reject. OmniSharp's primary configuration is the CLI `options` above.
            if so.settings and next(so.settings) then
                cfg.settings = so.settings
            end
            return cfg
        end,
    },
}
