-- lvim-lang.core.lsp: the bridge to lvim-lsp / lvim-ls.
-- lvim-lang NEVER owns an LSP lifecycle. A provider declares a CATALOG of servers (in
-- config.providers.<name>.lsp.servers) with a `default` that may be a string or a list; this
-- module fans that selection out to lvim-ls' additive register_language seam — one file_types
-- entry per chosen server (so several LSP clients can attach to the same buffer). The chosen
-- formatters / linters / debuggers / extra tools (from core.catalog.union_entry) ride on the
-- PRIMARY server's entry, so lvim-installer offers exactly the selected tools. The canonical
-- lvim-ls bootstrap then starts and manages each client. request() is a thin helper for a
-- provider's CUSTOM LSP methods (dart/textDocument/super, …) against the buffer's client.
--
---@module "lvim-lang.core.lsp"

local catalog = require("lvim-lang.core.catalog")

-- Every provider's server-config modules live under this require prefix (servers/<server>.lua).
local DIR_PREFIX = "lvim-lang.servers"

local M = {}

--- A file_types `lsp` list item for a server catalog entry (a string, or { name, bin } when the
--- binary differs), or nil when the server ships no mason package (e.g. dartls, bundled with the SDK).
---@param se table  server catalog entry
---@return string|table|nil
local function lsp_item(se)
    if not se.mason then
        return nil
    end
    return se.bin and { se.mason, bin = se.bin } or se.mason
end

--- Register a provider's chosen LSP servers with lvim-ls (additive; starts nothing itself). One
--- entry per chosen server — several clients attach to the same buffer when `default` is a list.
--- The FIRST (primary) server's entry carries the formatter/linter/debugger/tool install union.
---@param name string  provider name (its catalog lives in config.providers[name])
---@return nil
function M.register_catalog(name)
    local chosen = catalog.chosen_servers(name)
    if #chosen == 0 then
        return
    end
    local ok, lsp = pcall(require, "lvim-lsp")
    if not ok or type(lsp.register_language) ~= "function" then
        return
    end
    local union = catalog.union_entry(name)
    for i, key in ipairs(chosen) do
        local se = catalog.server_entry(name, key) or {}
        local item = lsp_item(se)
        -- A plain lvim-ls file_types entry ({ filetypes, lsp, formatters?, linters?, debuggers?, tools? }).
        local entry = { filetypes = se.filetypes or union.filetypes, lsp = item and { item } or {} }
        if i == 1 then
            -- Primary server carries the tool union so those installs are offered once.
            entry.formatters = union.formatters
            entry.linters = union.linters
            entry.debuggers = union.debuggers
            entry.tools = union.tools
        end
        -- The server-config module is <DIR_PREFIX>.<key> (servers/<key>.lua).
        lsp.register_language(key, entry, DIR_PREFIX)
    end
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
