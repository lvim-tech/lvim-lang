-- lvim-lang.providers.swift.test: Swift test running — the whole package and the XCTest method under
-- the cursor. The method under the cursor is found with treesitter (the enclosing `function_declaration`
-- and, when present, the enclosing XCTestCase `class_declaration`), and run with
-- `swift test --filter <Class>/<method>` — SwiftPM's `--filter` is a regex over `Module.Class/method`,
-- so `Class/method` selects exactly one test. All through core.runner → lvim-tasks (Test group, `gcc`
-- matcher — Swift's clang-style diagnostics).
--
---@module "lvim-lang.providers.swift.test"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The SwiftPM package root for the current buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "Package.swift", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `swift <argv…>` for a root through lvim-tasks (Test group, `gcc` matcher).
---@param root string
---@param argv string[]
---@param name string
---@return nil
local function run_swift(root, argv, name)
    local swift = toolchain.resolve("swift", "swift", root) or "swift"
    local cmd = { swift }
    vim.list_extend(cmd, argv)
    runner.run("swift", { name = name, cmd = cmd, cwd = root, group = "Test", matcher = "gcc" })
end

--- The `<Class>/<method>` filter for the XCTest method under the cursor (treesitter): the enclosing
--- `function_declaration` whose name starts with `test`, and the `class_declaration` that contains it.
--- Returns nil when the cursor is not inside a `test*` method.
---@param bufnr integer
---@return string|nil filter, string|nil method
local function enclosing_test(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil, nil
    end
    local method, class
    while node do
        local t = node:type()
        if not method and t == "function_declaration" then
            local name_node = node:field("name")[1]
            local name = name_node and vim.treesitter.get_node_text(name_node, bufnr) or nil
            if not name or not name:match("^test") then
                return nil, nil -- inside a non-test function
            end
            method = name
        elseif t == "class_declaration" then
            local name_node = node:field("name")[1]
            class = name_node and vim.treesitter.get_node_text(name_node, bufnr) or nil
            break
        end
        node = node:parent()
    end
    if not method then
        return nil, nil
    end
    -- With a class → `Class/method`; a free `test*` function (rare) → just the method name.
    return class and (class .. "/" .. method) or method, method
end

--- `:LvimLang test-func` — run the XCTest method under the cursor (`swift test --filter <Class>/<method>`).
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local filter, method = enclosing_test(ctx.bufnr)
    if not filter then
        vim.notify("lvim-lang: cursor is not inside an XCTest test method", vim.log.levels.WARN, TITLE)
        return
    end
    run_swift(root_of(ctx.bufnr), { "test", "--filter", filter }, "swift test " .. (method or filter))
end

return M
