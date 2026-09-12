-- lvim-lang.core.root: project-root resolution for the SAME marker list a server hands lvim-ls
-- (`lsp.root_patterns`): exact entry names (".git"), globs ("*.sln", "*.csproj"), or functions
-- `fun(dir): boolean`. A server module used to keep two answers — a function matcher for its own
-- `current_root()` and a plain name list for lvim-ls — and the two disagreed (lvim-ls stat'd ".sln"
-- as a literal name). One list, one rule, both sides.
--
---@module "lvim-lang.core.root"

local M = {}

--- A `vim.fs.root` matcher for `patterns` (called per directory entry as `(name, path)`).
---@param patterns (string|fun(dir: string): boolean)[]
---@return fun(name: string, path: string): boolean
function M.matcher(patterns)
    return function(name, path)
        for _, m in ipairs(patterns) do
            if type(m) == "function" then
                if m(path) == true then
                    return true
                end
            elseif type(m) == "string" then
                if m:find("[%*%?%[]") then
                    local pat = "^" .. vim.pesc(m):gsub("%%%*", ".*"):gsub("%%%?", ".") .. "$"
                    if name:match(pat) then
                        return true
                    end
                elseif name == m then
                    return true
                end
            end
        end
        return false
    end
end

--- The project root of the current buffer for `patterns` (its own directory when no marker is
--- found; the cwd for an unnamed buffer).
---@param patterns (string|fun(dir: string): boolean)[]
---@return string
function M.current(patterns)
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, M.matcher(patterns)) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

return M
