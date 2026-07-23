-- lvim-lang.providers.java.refactor: jdtls-driven refactorings under :LvimLang.
-- jdtls (Eclipse JDT.LS) exposes organize-imports as a server COMMAND and the extract refactorings as
-- code actions. organize-imports runs over the whole buffer — `java.edit.organizeImports` returns a
-- WorkspaceEdit we apply. The extracts (variable / constant / method) run over the VISUAL SELECTION and
-- go through Neovim's OWN `vim.lsp.buf.code_action` pipeline, filtered to jdtls' `refactor.extract`
-- actions and narrowed by keyword — so nvim drives the (command-backed, sometimes name-prompting)
-- refactor edit; we do not re-implement jdtls' refactoring protocol. Matching by keyword in the action
-- kind OR title keeps it working across jdtls versions that spell the sub-kind differently.
--
---@module "lvim-lang.providers.java.refactor"

local TITLE = { title = "lvim-lang" }

local M = {}

--- The jdtls client attached to the current buffer, or nil (with a warning).
---@return vim.lsp.Client|nil
local function client()
    local c = vim.lsp.get_clients({ name = "jdtls", bufnr = 0 })[1]
    if not c then
        vim.notify("lvim-lang: jdtls is not attached to this buffer", vim.log.levels.WARN, TITLE)
    end
    return c
end

--- `:LvimLang organize-imports` — drop unused imports and add/order the needed ones for the buffer.
---@param _args string[]
---@param _ctx table
---@return nil
function M.organize_imports(_args, _ctx)
    local c = client()
    if not c then
        return
    end
    local bufnr = vim.api.nvim_get_current_buf()
    local uri = vim.uri_from_bufnr(bufnr)
    c:request(
        "workspace/executeCommand",
        { command = "java.edit.organizeImports", arguments = { uri } },
        function(err, edit)
            if err then
                vim.notify(
                    "lvim-lang: organize imports failed: " .. tostring(err.message or err),
                    vim.log.levels.ERROR,
                    TITLE
                )
                return
            end
            if type(edit) == "table" and (edit.changes or edit.documentChanges) then
                vim.lsp.util.apply_workspace_edit(edit, c.offset_encoding or "utf-16")
            end
        end,
        bufnr
    )
end

--- Run a jdtls extract refactoring on the VISUAL SELECTION, via the code-action pipeline. `keyword`
--- selects which extraction ("variable" / "constant" / "method"): the request asks jdtls for all
--- `refactor.extract` actions over the range and the filter keeps the one whose kind OR title contains
--- the keyword — `apply = true` runs it (a picker only if several still match).
---@param keyword string
---@return nil
local function extract(keyword)
    if not client() then
        return
    end
    -- The last visual selection's marks: `{ row (1-based), col (0-based) }`, the shape code_action's
    -- `range` expects. `<` row 0 means no selection has been made yet.
    local s = vim.api.nvim_buf_get_mark(0, "<")
    local e = vim.api.nvim_buf_get_mark(0, ">")
    if s[1] == 0 then
        vim.notify("lvim-lang: select the code to extract first (visual mode)", vim.log.levels.WARN, TITLE)
        return
    end
    vim.lsp.buf.code_action({
        apply = true,
        range = { start = s, ["end"] = e },
        context = { only = { "refactor.extract" }, diagnostics = {} },
        filter = function(action)
            local kind = (action.kind or ""):lower()
            local title = (action.title or ""):lower()
            return kind:find(keyword, 1, true) ~= nil or title:find(keyword, 1, true) ~= nil
        end,
    })
end

--- `:LvimLang extract-variable` — extract the selection into a local variable.
---@param _args string[]
---@param _ctx table
---@return nil
function M.extract_variable(_args, _ctx)
    extract("variable")
end

--- `:LvimLang extract-constant` — extract the selection into a `static final` constant.
---@param _args string[]
---@param _ctx table
---@return nil
function M.extract_constant(_args, _ctx)
    extract("constant")
end

--- `:LvimLang extract-method` — extract the selection into a new method.
---@param _args string[]
---@param _ctx table
---@return nil
function M.extract_method(_args, _ctx)
    extract("method")
end

return M
