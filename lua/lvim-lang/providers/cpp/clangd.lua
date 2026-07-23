-- lvim-lang.providers.cpp.clangd: clangd-specific editor commands (the LSP extensions clangd adds
-- beyond the standard protocol) — switch between a source and its header, and show symbol info at the
-- cursor. Both need the RESPONSE of a custom request, so they drive the attached `clangd` client
-- directly (core.lsp.request is fire-and-forget against a named server).
--
---@module "lvim-lang.providers.cpp.clangd"

local TITLE = { title = "lvim-lang" }

local M = {}

--- The clangd client attached to `bufnr`, or nil (with a notice).
---@param bufnr integer
---@return table|nil
local function clangd_client(bufnr)
    local client = vim.lsp.get_clients({ bufnr = bufnr, name = "clangd" })[1]
    if not client then
        vim.notify("lvim-lang: no clangd client on this buffer", vim.log.levels.WARN, TITLE)
    end
    return client
end

--- `:LvimLang switch-header` — toggle between a `.c`/`.cpp` source and its `.h`/`.hpp` header via
--- clangd's `textDocument/switchSourceHeader` extension.
---@param _args string[]
---@param ctx table
---@return nil
function M.switch_header(_args, ctx)
    local bufnr = ctx.bufnr
    local client = clangd_client(bufnr)
    if not client then
        return
    end
    local params = vim.lsp.util.make_text_document_params(bufnr)
    client:request("textDocument/switchSourceHeader", params, function(err, result)
        if err or not result then
            vim.notify("lvim-lang: no corresponding source/header", vim.log.levels.INFO, TITLE)
            return
        end
        vim.cmd.edit(vim.uri_to_fname(result))
    end, bufnr)
end

--- `:LvimLang symbol-info` — show clangd's symbol metadata (name + container) for the symbol at the
--- cursor in a small float, via clangd's `textDocument/symbolInfo` extension.
---@param _args string[]
---@param ctx table
---@return nil
function M.symbol_info(_args, ctx)
    local bufnr = ctx.bufnr
    local client = clangd_client(bufnr)
    if not client then
        return
    end
    local params = vim.lsp.util.make_position_params(vim.api.nvim_get_current_win(), client.offset_encoding)
    client:request("textDocument/symbolInfo", params, function(err, res)
        if err or type(res) ~= "table" or #res == 0 then
            return
        end
        local name = ("name: %s"):format(res[1].name or "?")
        local container = ("container: %s"):format(res[1].containerName or "")
        vim.lsp.util.open_floating_preview({ name, container }, "", {
            height = 2,
            width = math.max(#name, #container),
            focusable = false,
            border = "single",
            title = "Symbol Info",
        })
    end, bufnr)
end

return M
