-- lvim-lang.providers.go.codegen: Go code generation — struct tags (gomodifytags), table-driven
-- tests (gotests) and interface stubs (impl). These MUTATE the buffer / write generated code rather
-- than run as tasks, so they call the tools directly with vim.system (async, off the UI thread) and
-- apply the result. Each tool is a mason package (config.providers.go.codegen); a missing one is
-- reported with a clear install hint instead of a raw error.
--
---@module "lvim-lang.providers.go.codegen"

local config = require("lvim-lang.config")
local ensure = require("lvim-lang.core.ensure")

local TITLE = { title = "lvim-lang" }

local M = {}

--- Resolve and ENSURE a codegen tool, then run `cb(binpath)`. An explicit config path is used
--- as-is; otherwise ensure.tool provides the binary (already on PATH → immediate; missing →
--- installed on demand through lvim-pkg, then the callback fires). So the tool a codegen command
--- needs is installed the first time you use that command.
---@param name string  codegen key (gomodifytags / gotests / impl)
---@param cb fun(binpath: string)
---@return nil
local function with_tool(name, cb)
    local entry = ((config.providers.go or {}).codegen or {})[name] or {}
    if entry.path and vim.fn.executable(entry.path) == 1 then
        return cb(entry.path)
    end
    ensure.tool(entry.mason or name, entry.bin or name, cb)
end

--- Write the buffer's current lines to a temp .go file (so codegen sees UNSAVED edits too), returning
--- the temp path (caller deletes it).
---@param bufnr integer
---@return string
local function buffer_to_temp(bufnr)
    local tmp = vim.fn.tempname() .. ".go"
    vim.fn.writefile(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), tmp)
    return tmp
end

--- The 1-based line range of the type/struct declaration enclosing the cursor, via treesitter.
---@param bufnr integer
---@return integer|nil start_line, integer|nil end_line
local function enclosing_struct_range(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil
    end
    while node do
        local t = node:type()
        if t == "type_declaration" or t == "type_spec" then
            local sr, _, er = node:range()
            return sr + 1, er + 1
        end
        node = node:parent()
    end
    return nil
end

--- The name of the function/method declaration enclosing the cursor, via treesitter.
---@param bufnr integer
---@return string|nil
local function enclosing_func_name(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil
    end
    while node do
        local t = node:type()
        if t == "function_declaration" or t == "method_declaration" then
            local name_node = node:field("name")[1]
            return name_node and vim.treesitter.get_node_text(name_node, bufnr) or nil
        end
        node = node:parent()
    end
    return nil
end

--- `:LvimLang tags <add|remove> [tags]` — add/remove struct tags on the struct under the cursor via
--- gomodifytags (default tags = "json"). Applies the tool's JSON patch to the buffer (no reload).
---@param args string[]
---@param ctx table
---@return nil
function M.tags(args, ctx)
    local action = args[1]
    if action ~= "add" and action ~= "remove" then
        vim.notify("lvim-lang: usage — :LvimLang tags <add|remove> [json|xml|…]", vim.log.levels.INFO, TITLE)
        return
    end
    local bufnr = ctx.bufnr
    local s_line, e_line = enclosing_struct_range(bufnr)
    if not s_line then
        vim.notify("lvim-lang: cursor is not inside a struct declaration", vim.log.levels.WARN, TITLE)
        return
    end
    local tags = args[2] or "json"
    local flag = action == "remove" and "-remove-tags" or "-add-tags"
    with_tool("gomodifytags", function(bin)
        local tmp = buffer_to_temp(bufnr)
        local cmd = { bin, "-file", tmp, "-line", s_line .. "," .. e_line, flag, tags, "-format", "json" }
        vim.system(cmd, { text = true }, function(res)
            vim.schedule(function()
                pcall(vim.fn.delete, tmp)
                if res.code ~= 0 then
                    vim.notify("lvim-lang: gomodifytags failed: " .. (res.stderr or ""), vim.log.levels.ERROR, TITLE)
                    return
                end
                local ok, data = pcall(vim.json.decode, res.stdout)
                if not ok or type(data) ~= "table" or not data.lines then
                    return
                end
                if vim.api.nvim_buf_is_valid(bufnr) then
                    vim.api.nvim_buf_set_lines(bufnr, data.start - 1, data["end"], false, data.lines)
                end
            end)
        end)
    end)
end

--- `:LvimLang gotests` — generate a table-driven test for the function under the cursor (gotests
--- `-only`), written to the package's _test.go file (reloaded via :checktime). Needs a saved file.
---@param _args string[]
---@param ctx table
---@return nil
function M.gotests(_args, ctx)
    local bufnr = ctx.bufnr
    local file = vim.api.nvim_buf_get_name(bufnr)
    if file == "" then
        return
    end
    if vim.bo[bufnr].modified then
        vim.notify("lvim-lang: save the file before generating tests", vim.log.levels.WARN, TITLE)
        return
    end
    local name = enclosing_func_name(bufnr)
    if not name then
        vim.notify("lvim-lang: cursor is not inside a function", vim.log.levels.WARN, TITLE)
        return
    end
    with_tool("gotests", function(bin)
        local cmd = { bin, "-only", "^" .. name .. "$", "-w", file }
        vim.system(cmd, { text = true }, function(res)
            vim.schedule(function()
                if res.code ~= 0 then
                    vim.notify("lvim-lang: gotests failed: " .. (res.stderr or ""), vim.log.levels.ERROR, TITLE)
                    return
                end
                vim.notify(("lvim-lang: generated tests for %s"):format(name), vim.log.levels.INFO, TITLE)
                pcall(vim.cmd, "checktime")
            end)
        end)
    end)
end

--- `:LvimLang impl <receiver> <interface>` — generate interface method stubs (impl), inserted below
--- the cursor. E.g. `:LvimLang impl r *Server io.Reader` (the LAST arg is the interface).
---@param args string[]
---@param ctx table
---@return nil
function M.impl(args, ctx)
    if #args < 2 then
        vim.notify(
            "lvim-lang: usage — :LvimLang impl <receiver…> <interface>  (e.g. r *Server io.Reader)",
            vim.log.levels.INFO,
            TITLE
        )
        return
    end
    local iface = args[#args]
    local receiver = table.concat({ unpack(args, 1, #args - 1) }, " ")
    local bufnr = ctx.bufnr
    local row = vim.api.nvim_win_get_cursor(0)[1]
    with_tool("impl", function(bin)
        vim.system({ bin, receiver, iface }, { text = true }, function(res)
            vim.schedule(function()
                if res.code ~= 0 or not res.stdout or res.stdout == "" then
                    vim.notify("lvim-lang: impl failed: " .. (res.stderr or "no output"), vim.log.levels.ERROR, TITLE)
                    return
                end
                local lines = vim.split(res.stdout:gsub("\n$", ""), "\n")
                if vim.api.nvim_buf_is_valid(bufnr) then
                    -- blank separator line, then the stubs, below the cursor line
                    table.insert(lines, 1, "")
                    vim.api.nvim_buf_set_lines(bufnr, row, row, false, lines)
                end
            end)
        end)
    end)
end

return M
