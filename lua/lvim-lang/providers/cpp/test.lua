-- lvim-lang.providers.cpp.test: run the C/C++ test under the cursor through CTest.
-- The enclosing GoogleTest (`TEST` / `TEST_F` / `TEST_P`) or Catch2 (`TEST_CASE` / `SCENARIO`) is
-- found with treesitter and mapped to the name CTest registers for it (GoogleTest → "Suite.Name",
-- Catch2 `TEST_CASE` → the case string, `SCENARIO` → "Scenario: <name>"), then run with
-- `ctest -R "^<name>$" --output-on-failure` in the build dir — the framework-agnostic path that
-- works whenever the project registers its tests with CTest (`gtest_discover_tests` /
-- `catch_discover_tests` / `add_test`). Through core.runner → lvim-tasks (Test group, `gcc` matcher).
--
-- Whole-project / file-level test running is `:LvimLang test` (tasks.lua). Per-test discovery with
-- richer result mapping lives in the lvim-test adapter; this is the quick "run the one at the cursor".
--
---@module "lvim-lang.providers.cpp.test"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local ts = vim.treesitter

local TITLE = { title = "lvim-lang" }

local M = {}

--- The cpp config block.
---@return table
local function opts()
    return config.providers.cpp or {}
end

--- Resolve the C/C++ project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "compile_commands.json", "CMakeLists.txt", "Makefile", ".clangd", ".git" })
            or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The CTest name of a GoogleTest `function_definition` (`TEST(Suite, Name)` → "Suite.Name"), or nil
--- when the node is not a GoogleTest macro.
---@param fdef TSNode  a `function_definition` node
---@param bufnr integer
---@return string|nil
local function gtest_name(fdef, bufnr)
    local decl = fdef:field("declarator")[1]
    if not decl or decl:type() ~= "function_declarator" then
        return nil
    end
    local id = decl:field("declarator")[1]
    if not id or id:type() ~= "identifier" then
        return nil
    end
    if not ts.get_node_text(id, bufnr):match("^TEST") then
        return nil
    end
    local params = decl:field("parameters")[1]
    if not params then
        return nil
    end
    local names = {}
    for c in params:iter_children() do
        if c:type() == "parameter_declaration" then
            names[#names + 1] = ts.get_node_text(c, bufnr)
        end
    end
    if #names >= 2 then
        return names[1] .. "." .. names[2]
    end
    return nil
end

--- The CTest name of a Catch2 `call_expression` (`TEST_CASE("x")` → "x"; `SCENARIO("x")` →
--- "Scenario: x" — the name Catch2 registers), or nil when it is not a Catch2 test macro.
---@param call TSNode  a `call_expression` node
---@param bufnr integer
---@return string|nil
local function catch2_name(call, bufnr)
    local fn = call:field("function")[1]
    if not fn then
        return nil
    end
    local macro = ts.get_node_text(fn, bufnr)
    if macro ~= "TEST_CASE" and macro ~= "SCENARIO" then
        return nil
    end
    local arglist = call:field("arguments")[1]
    if not arglist then
        return nil
    end
    for c in arglist:iter_children() do
        if c:type() == "string_literal" then
            local s = ts.get_node_text(c, bufnr):gsub('^"', ""):gsub('"$', "")
            return macro == "SCENARIO" and ("Scenario: " .. s) or s
        end
    end
    return nil
end

--- The CTest name of the GoogleTest / Catch2 test enclosing the cursor, via treesitter. Handles the
--- cursor being inside a GoogleTest body (its `function_definition` encloses it), on a Catch2 macro
--- line (the `call_expression`), or inside a Catch2 body (the body is the macro call's next sibling —
--- Catch2 does not nest the block under the call).
---@param bufnr integer
---@return string|nil
local function enclosing_test(bufnr)
    local ok, node = pcall(ts.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil
    end
    while node do
        local t = node:type()
        if t == "function_definition" then
            local name = gtest_name(node, bufnr)
            if name then
                return name
            end
        elseif t == "call_expression" then
            local name = catch2_name(node, bufnr)
            if name then
                return name
            end
        elseif t == "expression_statement" then
            -- Catch2: cursor on the macro line itself — the call is this statement's child.
            local call = node:named_child(0)
            if call and call:type() == "call_expression" then
                local name = catch2_name(call, bufnr)
                if name then
                    return name
                end
            end
        elseif t == "compound_statement" then
            -- Catch2: cursor inside the `{ }` body — the macro call is the block's previous sibling.
            local prev = node:prev_named_sibling()
            if prev and prev:type() == "expression_statement" then
                local call = prev:named_child(0)
                if call and call:type() == "call_expression" then
                    local name = catch2_name(call, bufnr)
                    if name then
                        return name
                    end
                end
            end
        end
        node = node:parent()
    end
    return nil
end

--- Escape a CTest regex (`-R` takes an ERE): backslash every metacharacter so the composed
--- `^<name>$` matches the test name literally (GoogleTest's `.`, Catch2's `[tags]`, spaces).
---@param s string
---@return string
local function ere_escape(s)
    return (s:gsub("[%.%^%$%*%+%?%(%)%[%]%{%}%\\|]", "\\%0"))
end

--- `:LvimLang test-func` — run the GoogleTest / Catch2 test under the cursor through CTest
--- (`ctest -R "^<name>$" --output-on-failure`). Requires a CMake project with registered tests.
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local bufnr = ctx.bufnr or vim.api.nvim_get_current_buf()
    local root = ctx.root or root_of(bufnr)
    if vim.fn.filereadable(root .. "/CMakeLists.txt") ~= 1 then
        vim.notify("lvim-lang: test-func needs a CMake project with CTest-registered tests", vim.log.levels.WARN, TITLE)
        return
    end
    local name = enclosing_test(bufnr)
    if not name then
        vim.notify("lvim-lang: cursor is not inside a GoogleTest / Catch2 test", vim.log.levels.WARN, TITLE)
        return
    end
    local dir = opts().build_dir or "build"
    local ctest = opts().ctest_path or "ctest"
    local cmd = { ctest, "--test-dir", dir, "-R", "^" .. ere_escape(name) .. "$", "--output-on-failure" }
    runner.run("cpp", { name = "ctest " .. name, cmd = cmd, cwd = root, group = "Test", matcher = "gcc" })
end

return M
