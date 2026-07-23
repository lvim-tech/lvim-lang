-- lvim-lang.providers.fsharp.test: F# test running — the whole project, the file, and the single
-- test binding under the cursor. The enclosing test is found with treesitter: a `declaration_expression`
-- (a module-body member) or `value_declaration` (a namespace top-level binding) whose `attributes`
-- carry a test attribute (xUnit `[<Fact>]`/`[<Theory>]`, NUnit `[<Test>]`/`[<TestCase>]`, FsCheck
-- `[<Property>]`), whose bound `let` name is the test. It is run with
-- `dotnet test --filter "FullyQualifiedName~<name>"` (VSTest's substring filter), through
-- core.runner → lvim-tasks (Test group, `typescript` .NET problem matcher).
--
-- Attribute-based tests are covered; the combinator style (Expecto `testCase "…"` inside a
-- `testList`) is NOT reliably discoverable by treesitter — those run via `:LvimLang test` (the whole
-- project) or `test-file`, which collect every attributed binding in the buffer.
--
---@module "lvim-lang.providers.fsharp.test"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

-- Attribute names that mark a binding as a test across the common frameworks. Matched as a substring
-- so a fully-qualified / suffixed form (`Xunit.FactAttribute`) still counts.
---@type string[]
local TEST_ATTRS = { "Fact", "Theory", "Test", "TestCase", "Property" }

local M = {}

--- Whether a directory entry name is an F# project-root marker (a solution / project file, the paket
--- manifest, or `.git`).
---@param name string
---@return boolean
local function is_root_marker(name)
    return name:match("%.sln$") ~= nil
        or name:match("%.fsproj$") ~= nil
        or name == "paket.dependencies"
        or name == ".git"
end

--- The .NET project/solution root for a buffer (nearest `.sln`/`.fsproj`/`paket.dependencies`, else
--- `.git`, else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, is_root_marker) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

-- The two node types that hold an attributed `let` binding: a module-body member
-- (`declaration_expression`) or a namespace top-level binding (`value_declaration`).
---@type table<string, boolean>
local BINDING_NODES = { declaration_expression = true, value_declaration = true }

--- Whether any of a node's `attributes` children names a test attribute.
---@param node any  a treesitter node (declaration_expression | value_declaration)
---@param bufnr integer
---@return boolean
local function has_test_attr(node, bufnr)
    for child in node:iter_children() do
        if child:type() == "attributes" then
            local text = vim.treesitter.get_node_text(child, bufnr) or ""
            for _, a in ipairs(TEST_ATTRS) do
                -- Word-ish boundary so `Test` does not spuriously match e.g. `Fastest`; `[<Test>]`,
                -- `[<Test;…>]` and `[<TestCase>]` are all covered.
                if text:find("[<%s;]" .. a .. "[>%s;(]") or text:find("<" .. a .. ">") then
                    return true
                end
            end
        end
    end
    return false
end

--- The bound `let` name of a binding node (its function / value binding name), or nil.
---@param decl any  a treesitter node (declaration_expression | value_declaration)
---@param bufnr integer
---@return string|nil
local function binding_name(decl, bufnr)
    for defn in decl:iter_children() do
        if defn:type() == "function_or_value_defn" then
            for left in defn:iter_children() do
                local t = left:type()
                if t == "function_declaration_left" or t == "value_declaration_left" then
                    -- The first identifier child of the *_left node is the binding name. Backtick-quoted
                    -- names (```let ``my test`` () =```) render with spaces in the FQN; keep the raw text.
                    for id in left:iter_children() do
                        if id:type() == "identifier" or id:type() == "long_identifier" then
                            local name = vim.treesitter.get_node_text(id, bufnr)
                            if name and name ~= "" then
                                return (name:gsub("`", ""))
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

--- The name of the test binding enclosing the cursor (treesitter), or nil. Walks up to the nearest
--- binding node (declaration_expression / value_declaration) that carries a test attribute.
---@param bufnr integer
---@return string|nil
local function enclosing_test(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil
    end
    local n = node
    while n do
        if BINDING_NODES[n:type()] and has_test_attr(n, bufnr) then
            return binding_name(n, bufnr)
        end
        n = n:parent()
    end
    return nil
end

--- Every attributed-test binding name in a buffer (treesitter), for `test-file`.
---@param bufnr integer
---@return string[]
local function file_tests(bufnr)
    local names = {}
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "fsharp")
    if not ok or not parser then
        return names
    end
    local tree = parser:parse()[1]
    if not tree then
        return names
    end
    local root = tree:root()
    local seen = {}
    --- Recurse, collecting attributed binding nodes.
    ---@param node any
    local function walk(node)
        if BINDING_NODES[node:type()] and has_test_attr(node, bufnr) then
            local name = binding_name(node, bufnr)
            if name and not seen[name] then
                seen[name] = true
                names[#names + 1] = name
            end
        end
        for child in node:iter_children() do
            walk(child)
        end
    end
    walk(root)
    return names
end

--- Run `dotnet test <argv…>` at a root through lvim-tasks (Test group, `typescript` .NET matcher).
---@param root string
---@param argv string[]
---@param name string
---@return nil
local function run_test(root, argv, name)
    local dotnet = toolchain.resolve("fsharp", "dotnet", root) or "dotnet"
    local cmd = { dotnet, "test" }
    vim.list_extend(cmd, argv)
    runner.run("fsharp", { name = name, cmd = cmd, cwd = root, group = "Test", matcher = "typescript" })
end

--- `:LvimLang test-func` — run the single test binding under the cursor via
--- `dotnet test --filter "FullyQualifiedName~<name>"`.
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local name = enclosing_test(ctx.bufnr)
    if not name then
        vim.notify(
            "lvim-lang: cursor is not inside a [<Fact>]/[<Theory>]/[<Test>]/[<TestCase>]/[<Property>] binding",
            vim.log.levels.WARN,
            TITLE
        )
        return
    end
    run_test(ctx.root or root_of(ctx.bufnr), { "--filter", "FullyQualifiedName~" .. name }, "dotnet test " .. name)
end

--- `:LvimLang test-file` — run every attributed test binding in the current buffer, OR-ed into one
--- `--filter`. Falls back to a warning when no attributed test is found (combinator-style Expecto
--- suites are not discoverable — use `:LvimLang test` for those).
---@param _args string[]
---@param ctx table
---@return nil
function M.file(_args, ctx)
    local bufnr = ctx.bufnr or vim.api.nvim_get_current_buf()
    local names = file_tests(bufnr)
    if #names == 0 then
        vim.notify(
            "lvim-lang: no [<Fact>]/[<Test>]/… binding found in this file — run `:LvimLang test` for the project",
            vim.log.levels.WARN,
            TITLE
        )
        return
    end
    local filters = {}
    for _, n in ipairs(names) do
        filters[#filters + 1] = "FullyQualifiedName~" .. n
    end
    run_test(ctx.root or root_of(bufnr), { "--filter", table.concat(filters, "|") }, "dotnet test (file)")
end

return M
