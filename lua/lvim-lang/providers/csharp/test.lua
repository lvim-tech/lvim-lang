-- lvim-lang.providers.csharp.test: C# test running — the whole project, the file, and the single
-- test method under the cursor. The enclosing test method is found with treesitter: a
-- `method_declaration` whose attribute list carries a test attribute (xUnit `[Fact]`/`[Theory]`,
-- NUnit `[Test]`/`[TestCase]`, MSTest `[TestMethod]`), plus the enclosing `class_declaration` for
-- the class name. It is run with `dotnet test --filter "FullyQualifiedName~<Class.Method>"`
-- (VSTest's substring filter), through core.runner → lvim-tasks (Test group, `typescript` C#
-- problem matcher).
--
---@module "lvim-lang.providers.csharp.test"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

-- Attribute names that mark a method as a test across the three common frameworks. Matched as a
-- substring so a fully-qualified / suffixed form (`Xunit.FactAttribute`) still counts.
---@type string[]
local TEST_ATTRS = { "Fact", "Theory", "Test", "TestMethod", "TestCase" }

local M = {}

--- Whether a directory entry name is a C# project-root marker (a solution / project file, or `.git`).
---@param name string
---@return boolean
local function is_root_marker(name)
    return name:match("%.sln$") ~= nil or name:match("%.csproj$") ~= nil or name == ".git"
end

--- The .NET project/solution root for a buffer (nearest `.sln`/`.csproj`, else `.git`, else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, is_root_marker) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Whether any of a node's `attribute_list` children names a test attribute.
---@param node any  a treesitter node (method_declaration)
---@param bufnr integer
---@return boolean
local function has_test_attr(node, bufnr)
    for child in node:iter_children() do
        if child:type() == "attribute_list" then
            for attr in child:iter_children() do
                if attr:type() == "attribute" then
                    local name_node = attr:field("name")[1]
                    local text = name_node and vim.treesitter.get_node_text(name_node, bufnr) or ""
                    for _, a in ipairs(TEST_ATTRS) do
                        if text:find(a, 1, true) then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

--- The `Class.Method` name of the test enclosing the cursor (treesitter), or nil. Walks up to the
--- nearest `method_declaration` that carries a test attribute, then to its `class_declaration`.
---@param bufnr integer
---@return string|nil
local function enclosing_test(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil
    end
    local method
    local n = node
    while n do
        if n:type() == "method_declaration" then
            method = n
            break
        end
        n = n:parent()
    end
    if not method or not has_test_attr(method, bufnr) then
        return nil
    end
    local mname_node = method:field("name")[1]
    local mname = mname_node and vim.treesitter.get_node_text(mname_node, bufnr) or nil
    if not mname then
        return nil
    end
    -- Walk up to the enclosing class for a qualified `Class.Method` filter (more selective).
    local cls = method:parent()
    while cls do
        if cls:type() == "class_declaration" or cls:type() == "record_declaration" then
            local cname_node = cls:field("name")[1]
            local cname = cname_node and vim.treesitter.get_node_text(cname_node, bufnr) or nil
            if cname then
                return cname .. "." .. mname
            end
            break
        end
        cls = cls:parent()
    end
    return mname
end

--- Run `dotnet test <argv…>` at a root through lvim-tasks (Test group, `typescript` C# matcher).
---@param root string
---@param argv string[]
---@param name string
---@return nil
local function run_test(root, argv, name)
    local dotnet = toolchain.resolve("csharp", "dotnet", root) or "dotnet"
    local cmd = { dotnet, "test" }
    vim.list_extend(cmd, argv)
    runner.run("csharp", { name = name, cmd = cmd, cwd = root, group = "Test", matcher = "typescript" })
end

--- `:LvimLang test-func` — run the single test method under the cursor via
--- `dotnet test --filter "FullyQualifiedName~Class.Method"`.
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local name = enclosing_test(ctx.bufnr)
    if not name then
        vim.notify(
            "lvim-lang: cursor is not inside a [Fact]/[Theory]/[Test]/[TestMethod] method",
            vim.log.levels.WARN,
            TITLE
        )
        return
    end
    run_test(ctx.root or root_of(ctx.bufnr), { "--filter", "FullyQualifiedName~" .. name }, "dotnet test " .. name)
end

--- `:LvimLang test-file` — run every test whose type name matches the current buffer's class. Uses
--- the file's base name as the class filter (the C# convention: one public test class per file).
---@param _args string[]
---@param ctx table
---@return nil
function M.file(_args, ctx)
    local buf = vim.api.nvim_buf_get_name(ctx.bufnr)
    if buf == "" then
        vim.notify("lvim-lang: no file for this buffer", vim.log.levels.WARN, TITLE)
        return
    end
    local class = vim.fn.fnamemodify(buf, ":t:r")
    run_test(
        ctx.root or root_of(ctx.bufnr),
        { "--filter", "FullyQualifiedName~" .. class .. "." },
        "dotnet test (file: " .. class .. ")"
    )
end

return M
