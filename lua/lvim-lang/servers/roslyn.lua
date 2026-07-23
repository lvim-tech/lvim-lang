-- lvim-lang.servers.roslyn: the lvim-ls server-config module for the roslyn language server
-- (Microsoft.CodeAnalysis.LanguageServer) — the OPT-IN alternative C# LSP (OmniSharp is the default).
-- Loaded by the lvim-ls manager only when the user selects it (providers.csharp.lsp.server =
-- "roslyn"), via the "lvim-lang.servers" dir prefix that core.lsp registers. lvim-lang does NOT own
-- the LSP lifecycle — this module only DESCRIBES the server; the canonical lvim-ls bootstrap starts
-- and manages the client.
--
-- Roslyn-in-Neovim needs a non-trivial bootstrap that OmniSharp does not: the server speaks stdio
-- (`--stdio`) but does NOT open the workspace from the LSP `rootUri`. It must be told the workspace
-- EXPLICITLY, AFTER initialization, with a custom `solution/open` notification (a `.sln`) or
-- `project/open` (one or more `.csproj`). This module resolves the binary per root through
-- core.toolchain and sends that notification on attach. EXPERIMENTAL: the roslyn server's protocol
-- extensions evolve; prefer OmniSharp unless you specifically need roslyn.
--
---@module "lvim-lang.servers.roslyn"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local csharp_dap = require("lvim-lang.providers.csharp.dap")

--- The C# provider's config block.
---@return table
local function opts()
    return config.providers.csharp or {}
end

--- The roslyn server catalog entry (settings / cmd override), from
--- config.providers.csharp.lsp.servers.roslyn.
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.roslyn) or {}
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

--- Files under `root` (non-recursive) whose name matches `pattern` (a Lua pattern), as absolute paths.
---@param root string
---@param pattern string
---@return string[]
local function files_matching(root, pattern)
    local out = {}
    for name, kind in vim.fs.dir(root) do
        if kind == "file" and name:match(pattern) then
            out[#out + 1] = vim.fs.joinpath(root, name)
        end
    end
    return out
end

-- Clients whose workspace has already been opened, keyed by client id — so the `solution/open`
-- notification is sent exactly once per server, not once per attached buffer (no field is injected
-- into the client object).
---@type table<integer, boolean>
local opened = {}

--- Tell the roslyn server which workspace to open: a `solution/open` for the nearest `.sln`, else a
--- `project/open` for every `.csproj` in the root. Roslyn needs this AFTER initialize — hence on_attach.
---@param client table  the LSP client
---@param root string
---@return nil
local function open_workspace(client, root)
    local slns = files_matching(root, "%.sln$")
    if #slns > 0 then
        client:notify("solution/open", { solution = vim.uri_from_fname(slns[1]) })
        return
    end
    local csprojs = files_matching(root, "%.csproj$")
    if #csprojs > 0 then
        local uris = {}
        for _, p in ipairs(csprojs) do
            uris[#uris + 1] = vim.uri_from_fname(p)
        end
        client:notify("project/open", { projects = uris })
    end
end

return {
    -- netcoredbg adapter + base C# debug configurations (auto-registered with lvim-dap on attach).
    dap = csharp_dap.spec(),
    -- Per-filetype formatter/linter routing (chosen tools only; empty when none selected).
    efm = catalog.efm_groups("csharp"),
    lsp = {
        root_patterns = { ".sln", ".csproj", ".git" },
        --- Built fresh per root so the roslyn binary tracks the project's SDK (version manager / PATH).
        ---@return table
        config = function()
            local so = server_opts()
            local root = current_root()
            local roslyn = toolchain.resolve("csharp", "Microsoft.CodeAnalysis.LanguageServer", root)
                or "Microsoft.CodeAnalysis.LanguageServer"
            local log_dir = vim.fs.joinpath(vim.fn.stdpath("cache"), "lvim-lang", "roslyn")
            pcall(vim.fn.mkdir, log_dir, "p")
            local cmd = so.cmd or { roslyn, "--logLevel", "Information", "--extensionLogDirectory", log_dir, "--stdio" }
            local base_on_attach = catalog.lsp_on_attach("csharp", "roslyn")
            local cfg = {
                cmd = cmd,
                filetypes = { "cs" },
                capabilities = capabilities(),
                ---@param client table  the LSP client
                ---@param bufnr integer
                on_attach = function(client, bufnr)
                    base_on_attach(client, bufnr)
                    -- Open the workspace once per client (roslyn does not read rootUri).
                    if client.id and not opened[client.id] then
                        opened[client.id] = true
                        pcall(open_workspace, client, current_root())
                    end
                end,
            }
            if so.settings and next(so.settings) then
                cfg.settings = so.settings
            end
            return cfg
        end,
    },
}
