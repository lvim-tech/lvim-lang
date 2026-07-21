-- lvim-lang.core.lsp: the bridge to lvim-lsp / lvim-ls.
-- lvim-lang NEVER owns an LSP lifecycle. A provider declares its server (file_types entry +
-- a server-config module dir prefix) and this module hands that to lvim-ls' additive
-- register_language seam; the canonical lvim-ls bootstrap then starts and manages the client
-- like any other. request() is a thin helper for the provider's CUSTOM LSP methods
-- (dart/textDocument/super, dart/reanalyze, …) against the buffer's client.
--
-- Implemented in milestone M2. The stub keeps registry activation safe before then.
--
---@module "lvim-lang.core.lsp"

---@class LvimLangLspSpec
---@field server     string   Server name (e.g. "dart"); the server-config module is <dir_prefix>.<server>
---@field file_types table    lvim-ls LvimFiletypeEntry ({ filetypes, lsp = {}, formatters?, … })
---@field dir_prefix string   require prefix holding the server-config module (e.g. "lvim-lang.servers")

local M = {}

--- Register a language's LSP with lvim-ls (additive; does not start anything itself).
---@param spec LvimLangLspSpec
---@return nil
function M.register(spec)
    local ok, lsp = pcall(require, "lvim-lsp")
    if not ok or type(lsp.register_language) ~= "function" then
        return -- M2 adds register_language to lvim-ls/lvim-lsp
    end
    lsp.register_language(spec.server, spec.file_types, spec.dir_prefix)
end

--- Send a custom LSP request to the server attached to `bufnr`.
---@param bufnr integer
---@param server string
---@param method string
---@param params table|nil
---@param cb? fun(err: any, result: any)
---@return nil
function M.request(bufnr, server, method, params, cb)
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = server })) do
        client:request(method, params, cb, bufnr)
        return
    end
end

return M
