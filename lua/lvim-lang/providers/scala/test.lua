-- lvim-lang.providers.scala.test: test running at SUITE (class) granularity through the build tool.
-- The enclosing test suite under the cursor is found with treesitter (the enclosing
-- `class_definition` / `object_definition` / `trait_definition` + the file's `package_clause`) and
-- addressed to the build tool: sbt filters with `testOnly <pkg>.<Class>`, mill with
-- `<module>.test.testOnly <pkg>.<Class>`, bloop with `test <project> -o <pkg>.<Class>`. Runs go
-- through core.runner → lvim-tasks (Test group, `generic` matcher). Whole-suite running is
-- `:LvimLang test` (see tasks.lua); this module adds the current-file / current-suite targets.
--
-- Scala test frameworks (ScalaTest / munit / utest / specs2) express individual tests as a DSL, not
-- as named methods, and the single-test selector differs per framework (ScalaTest `-- -z`, munit
-- `-- --tests=`), so there is no clean cross-framework way to run ONE DSL test. `test-func` therefore
-- runs the enclosing SUITE (with a one-time notice) — the finest granularity that works everywhere.
--
---@module "lvim-lang.providers.scala.test"

local runner = require("lvim-lang.core.runner")
local buildtool = require("lvim-lang.providers.scala.buildtool")

local TITLE = { title = "lvim-lang" }

-- Scala's project-root markers (build scripts, then `.git`).
---@type string[]
local ROOT_PATTERNS = { "build.sbt", "build.sc", ".git" }

---@type table<string, boolean>  one-time "test-func runs the whole suite" notice, per root
local func_notified = {}

local M = {}

--- The Scala project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, ROOT_PATTERNS) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The buffer's `package …` name via treesitter (a `package_clause`'s identifier), or nil for the
--- root package.
---@param bufnr integer
---@return string|nil
local function package_name(bufnr)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "scala")
    if not ok or not parser then
        return nil
    end
    local tree = (parser:parse() or {})[1]
    if not tree then
        return nil
    end
    for node in tree:root():iter_children() do
        if node:type() == "package_clause" then
            for child in node:iter_children() do
                local t = child:type()
                if t == "package_identifier" or t == "stable_identifier" or t == "identifier" then
                    return vim.treesitter.get_node_text(child, bufnr)
                end
            end
        end
    end
    return nil
end

--- The (outermost) enclosing test suite name under the cursor, via treesitter — a `class_definition`
--- / `object_definition` / `trait_definition`'s `name` identifier. Outermost wins (a suite is
--- addressed by its top-level type).
---@param bufnr integer
---@return string|nil
local function enclosing_suite(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil
    end
    local suite
    while node do
        local t = node:type()
        if t == "class_definition" or t == "object_definition" or t == "trait_definition" then
            local n = node:field("name")[1]
            if n then
                suite = vim.treesitter.get_node_text(n, bufnr) -- keep walking → outermost wins
            end
        end
        node = node:parent()
    end
    return suite
end

--- A fully-qualified suite name from a package + simple name (`pkg.Suite`, or just `Suite` in the
--- root package).
---@param pkg string|nil
---@param suite string
---@return string
local function fqcn(pkg, suite)
    return pkg and (pkg .. "." .. suite) or suite
end

--- Run the build tool's test task filtered to a single suite `fqcn`, at `root`, through lvim-tasks.
--- Returns false (after a notice) when the tool is missing / mill has no configured module.
---@param root string
---@param fqcn_name string
---@param label string
---@return boolean
local function run_suite(root, fqcn_name, label)
    local tool = buildtool.detect(root)
    if not tool then
        vim.notify("lvim-lang: no sbt / mill / bloop project found", vim.log.levels.WARN, TITLE)
        return false
    end
    local cmd = buildtool.base(tool, root)
    if tool == "sbt" then
        cmd[#cmd + 1] = "testOnly " .. fqcn_name -- one sbt command string
    elseif tool == "mill" then
        local mod = buildtool.module(root)
        if not mod then
            vim.notify(
                "lvim-lang: mill needs a module to filter tests — set providers.scala.mill_module",
                vim.log.levels.WARN,
                TITLE
            )
            return false
        end
        vim.list_extend(cmd, { mod .. ".test.testOnly", fqcn_name })
    else -- bloop
        vim.list_extend(cmd, { "test", buildtool.project(root), "-o", fqcn_name })
    end
    runner.run("scala", { name = label, cmd = cmd, cwd = root, group = "Test", matcher = "generic" })
    return true
end

--- `:LvimLang test-file` — run every test in the current buffer's suite (`testOnly pkg.Suite`).
--- Falls back to the file's basename when no suite type is found (a Scala suite usually matches its
--- file name).
---@param _args string[]
---@param ctx table
---@return nil
function M.file(_args, ctx)
    local bufnr = ctx.bufnr
    local suite = enclosing_suite(bufnr)
    if not suite then
        local name = vim.api.nvim_buf_get_name(bufnr)
        suite = name ~= "" and vim.fn.fnamemodify(name, ":t:r") or nil
    end
    if not suite then
        vim.notify("lvim-lang: no test suite for this buffer", vim.log.levels.WARN, TITLE)
        return
    end
    local pkg = package_name(bufnr)
    run_suite(ctx.root or root_of(bufnr), fqcn(pkg, suite), "test " .. suite)
end

--- `:LvimLang test-func` — Scala test frameworks have no clean cross-framework single-test selector,
--- so this runs the enclosing SUITE (the finest granularity that works everywhere), with a one-time
--- notice explaining the class-level scope.
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local bufnr = ctx.bufnr
    local suite = enclosing_suite(bufnr)
    if not suite then
        vim.notify("lvim-lang: cursor is not inside a test suite", vim.log.levels.WARN, TITLE)
        return
    end
    local root = ctx.root or root_of(bufnr)
    if not func_notified[root] then
        func_notified[root] = true
        vim.notify(
            "lvim-lang: Scala test isolation is per-suite — running the whole " .. suite .. " suite.",
            vim.log.levels.INFO,
            TITLE
        )
    end
    local pkg = package_name(bufnr)
    run_suite(root, fqcn(pkg, suite), "test " .. suite)
end

return M
