-- lvim-lang.providers.php.test: PHPUnit test running — the whole file and the single test method
-- under the cursor. The enclosing test is found with treesitter (the nearest `method_declaration` +
-- its enclosing `class_declaration`) and addressed to PHPUnit: the current buffer's file scopes the
-- run and `--filter <method>` selects the one method (PHPUnit matches the filter against the test
-- method name). Runs go through core.runner → lvim-tasks (Test group, `generic` matcher). Whole-suite
-- running is `:LvimLang test` (see tasks.lua); this module adds the granular targets.
--
---@module "lvim-lang.providers.php.test"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The PHP project root for a buffer (nearest `composer.json`, else `.git`, else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "composer.json", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The enclosing test method + its (outermost) class under the cursor, via treesitter. Returns the
--- class name and the method name; either is nil when the cursor is not inside one.
---@param bufnr integer
---@return string|nil class, string|nil method
local function enclosing(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil, nil
    end
    local class, method
    while node do
        local t = node:type()
        if t == "method_declaration" and not method then
            local n = node:field("name")[1]
            method = n and vim.treesitter.get_node_text(n, bufnr) or nil
        elseif t == "class_declaration" then
            -- Keep walking so the OUTERMOST class wins (a test file's top-level class).
            local n = node:field("name")[1]
            class = n and vim.treesitter.get_node_text(n, bufnr) or class
        end
        node = node:parent()
    end
    return class, method
end

--- Run PHPUnit at a root through lvim-tasks (Test group, `generic` matcher). `argv` is appended after
--- the resolved `phpunit` binary.
---@param root string
---@param argv string[]
---@param name string
---@return nil
local function run_phpunit(root, argv, name)
    local phpunit = toolchain.resolve("php", "phpunit", root) or "phpunit"
    local cmd = { phpunit }
    vim.list_extend(cmd, argv)
    runner.run("php", { name = name, cmd = cmd, cwd = root, group = "Test", matcher = "generic" })
end

--- `:LvimLang test-func` — run the single PHPUnit method under the cursor
--- (`phpunit --filter <method> <file>`).
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local bufnr = ctx.bufnr or vim.api.nvim_get_current_buf()
    local _, method = enclosing(bufnr)
    if not method then
        vim.notify("lvim-lang: cursor is not inside a test method", vim.log.levels.WARN, TITLE)
        return
    end
    local file = vim.api.nvim_buf_get_name(bufnr)
    local argv = { "--filter", method }
    if file ~= "" then
        argv[#argv + 1] = file
    end
    run_phpunit(ctx.root or root_of(bufnr), argv, "phpunit " .. method)
end

--- `:LvimLang test-file` — run every PHPUnit test in the current buffer's file (`phpunit <file>`).
---@param _args string[]
---@param ctx table
---@return nil
function M.file(_args, ctx)
    local bufnr = ctx.bufnr or vim.api.nvim_get_current_buf()
    local file = vim.api.nvim_buf_get_name(bufnr)
    if file == "" then
        vim.notify("lvim-lang: no file for this buffer", vim.log.levels.WARN, TITLE)
        return
    end
    run_phpunit(ctx.root or root_of(bufnr), { file }, "phpunit " .. vim.fs.basename(file))
end

return M
