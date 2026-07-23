-- lvim-lang.providers.java.decompile: open `jdt://` decompiled library sources.
-- When you go-to-definition on a class whose source jar is NOT attached, jdtls answers with a
-- `jdt://…` URI instead of a file path. That URI is not a real file — Neovim would open an empty
-- buffer — so jdtls exposes the class' text through the CUSTOM `java/classFileContents` request. This
-- module registers a single `BufReadCmd jdt://*` autocmd (once per session) that fetches that text,
-- fills a read-only `java` buffer with it, and attaches the jdtls client so hover / go-to-definition
-- keep working inside the decompiled source. This is the canonical Eclipse JDT.LS seam (the same one
-- the VS Code Java extension uses), not a side-channel. `contentProvider.preferred = "fernflower"` in
-- the server settings selects the decompiler jdtls hands back.
--
---@module "lvim-lang.providers.java.decompile"

local M = {}

--- Augroup name for the one-shot `jdt://` handler.
local GROUP = "LvimLangJavaJdt"

---@type boolean  the BufReadCmd handler is installed (install exactly once per session)
local installed = false

--- The jdtls client serving `bufnr`, else any attached jdtls client, else nil.
---@param bufnr integer
---@return vim.lsp.Client|nil
local function jdtls_client(bufnr)
    local clients = vim.lsp.get_clients({ name = "jdtls", bufnr = bufnr })
    return clients[1] or vim.lsp.get_clients({ name = "jdtls" })[1]
end

--- Fetch the decompiled/attached source for `uri` from jdtls and write it into `bufnr` — read-only,
--- filetype `java`, with the jdtls client attached so LSP features work inside it. A no-op (leaving the
--- buffer empty) when no jdtls client is attached yet.
---@param bufnr integer
---@param uri string  the `jdt://…` URI being read
---@return nil
local function load(bufnr, uri)
    local client = jdtls_client(bufnr)
    if not client then
        return
    end
    -- `java/classFileContents` takes a TextDocumentIdentifier and returns the class' text as a string.
    client:request("java/classFileContents", { uri = uri }, function(err, content)
        if err or type(content) ~= "string" or not vim.api.nvim_buf_is_valid(bufnr) then
            return
        end
        local lines = vim.split(content, "\r\n?", { plain = false })
        vim.bo[bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.bo[bufnr].modifiable = false
        vim.bo[bufnr].modified = false
        vim.bo[bufnr].buftype = "nofile"
        vim.bo[bufnr].filetype = "java"
        vim.bo[bufnr].readonly = true
        -- Attach the SAME jdtls client so hover / definition / references resolve inside the decompiled
        -- source (a further jump lands on another jdt:// buffer, handled by this same autocmd).
        pcall(vim.lsp.buf_attach_client, bufnr, client.id)
    end, bufnr)
end

--- Install the `jdt://` content handler ONCE. Idempotent — safe to call from every root activation.
---@return nil
function M.setup()
    if installed then
        return
    end
    installed = true
    local group = vim.api.nvim_create_augroup(GROUP, { clear = true })
    vim.api.nvim_create_autocmd("BufReadCmd", {
        group = group,
        pattern = "jdt://*",
        desc = "lvim-lang: load jdtls decompiled sources for a jdt:// URI",
        callback = function(ev)
            load(ev.buf, ev.match)
        end,
    })
end

return M
