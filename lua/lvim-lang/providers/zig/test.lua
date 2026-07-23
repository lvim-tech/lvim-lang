-- lvim-lang.providers.zig.test: run the Zig test under the cursor.
-- A Zig test is a `test "name" { … }` block (or `test <decl> { … }`); the enclosing
-- `test_declaration` is found with treesitter and its NAME (the string literal, quotes stripped —
-- or the identifier) is passed to `zig test <file> --test-filter <name>`. Zig's `--test-filter`
-- matches a SUBSTRING of the fully-qualified test name (`<module>.test.<name>`), so filtering by the
-- block's own name runs exactly it. Per-file `zig test` compiles the file's own tests regardless of
-- a build.zig, so this works in both single-file and project layouts. Through core.runner →
-- lvim-tasks (Test group, `gcc` matcher).
--
-- Whole-project / whole-file test running is `:LvimLang test` (tasks.lua); richer per-test result
-- mapping lives in the lvim-test adapter — this is the quick "run the one at the cursor".
--
---@module "lvim-lang.providers.zig.test"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local ts = vim.treesitter

local TITLE = { title = "lvim-lang" }

local M = {}

--- The Zig project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "build.zig", "build.zig.zon", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The name of the `test_declaration` enclosing the cursor (treesitter): the string literal with
--- its surrounding quotes stripped, or the identifier for a decltest. nil when the cursor is not
--- inside a named test (an anonymous `test { … }` has no name to filter on).
---@param bufnr integer
---@return string|nil
local function enclosing_test(bufnr)
    local ok, node = pcall(ts.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil
    end
    while node do
        if node:type() == "test_declaration" then
            -- The name is the FIRST named child before the block: a `string` (named test) or an
            -- `identifier` (decltest). Anonymous tests have neither.
            for c in node:iter_children() do
                local t = c:type()
                if t == "string" then
                    return (ts.get_node_text(c, bufnr):gsub('^"', ""):gsub('"$', ""))
                elseif t == "identifier" then
                    return ts.get_node_text(c, bufnr)
                elseif t == "block" then
                    break
                end
            end
            return nil
        end
        node = node:parent()
    end
    return nil
end

--- `:LvimLang test-func` — run the `test` block under the cursor
--- (`zig test <file> --test-filter <name>`).
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local bufnr = ctx.bufnr or vim.api.nvim_get_current_buf()
    local file = vim.api.nvim_buf_get_name(bufnr)
    if file == "" then
        vim.notify("lvim-lang: no file for the test under the cursor", vim.log.levels.WARN, TITLE)
        return
    end
    local name = enclosing_test(bufnr)
    if not name then
        vim.notify("lvim-lang: cursor is not inside a named `test` block", vim.log.levels.WARN, TITLE)
        return
    end
    local root = ctx.root or root_of(bufnr)
    local zig = toolchain.resolve("zig", "zig", root) or "zig"
    local cmd = { zig, "test", file, "--test-filter", name }
    runner.run("zig", {
        name = "zig test " .. name,
        cmd = cmd,
        cwd = vim.fs.dirname(file),
        group = "Test",
        matcher = "gcc",
    })
end

return M
