-- lvim-lang.providers.kotlin.test: JUnit / kotlin.test running — the whole suite, the current file,
-- and the test under the cursor. The cursor test is found with treesitter (the enclosing
-- `function_declaration` + its enclosing `class_declaration`/`object_declaration` + the file's
-- `package_header`) and addressed to the build tool: Gradle filters with
-- `--tests "<pkg>.<Class>.<method>"`, Maven with `-Dtest=<Class>#<method>` (Surefire). Runs go through
-- core.runner → lvim-tasks (Test group, `generic` matcher). Whole-suite running is `:LvimLang test`
-- (see tasks.lua); this module adds the granular targets.
--
---@module "lvim-lang.providers.kotlin.test"

local runner = require("lvim-lang.core.runner")
local buildtool = require("lvim-lang.providers.kotlin.buildtool")

local TITLE = { title = "lvim-lang" }

-- Kotlin's project-root markers (Gradle scripts / wrapper, then Maven, then `.git`).
---@type string[]
local ROOT_PATTERNS = {
    "build.gradle.kts",
    "build.gradle",
    "settings.gradle.kts",
    "settings.gradle",
    "pom.xml",
    ".git",
}

local M = {}

--- The Kotlin project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, ROOT_PATTERNS) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The buffer's `package …` name via treesitter (a `package_header`'s identifier), or nil for the
--- default package.
---@param bufnr integer
---@return string|nil
local function package_name(bufnr)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "kotlin")
    if not ok or not parser then
        return nil
    end
    local tree = (parser:parse() or {})[1]
    if not tree then
        return nil
    end
    for node in tree:root():iter_children() do
        if node:type() == "package_header" then
            for child in node:iter_children() do
                if child:type() == "identifier" then
                    return vim.treesitter.get_node_text(child, bufnr)
                end
            end
        end
    end
    return nil
end

--- The enclosing test function + its (outermost) class/object under the cursor, via treesitter. In
--- the Kotlin grammar a `function_declaration` names its function with a `simple_identifier` and a
--- `class_declaration` / `object_declaration` names its type with a `type_identifier`.
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
        if t == "function_declaration" and not method then
            for child in node:iter_children() do
                if child:type() == "simple_identifier" then
                    method = vim.treesitter.get_node_text(child, bufnr)
                    break
                end
            end
        elseif t == "class_declaration" or t == "object_declaration" then
            -- Keep walking so the OUTERMOST type wins (JUnit addresses by the top-level class).
            for child in node:iter_children() do
                if child:type() == "type_identifier" then
                    class = vim.treesitter.get_node_text(child, bufnr)
                    break
                end
            end
        end
        node = node:parent()
    end
    return class, method
end

--- A fully-qualified class name from a package + simple class name (`pkg.Class`, or just `Class`
--- in the default package).
---@param pkg string|nil
---@param class string
---@return string
local function fqcn(pkg, class)
    return pkg and (pkg .. "." .. class) or class
end

--- Run the build tool's `test` task filtered to a Gradle `--tests` pattern / a Maven `-Dtest`
--- selector, at `root`, through lvim-tasks.
---@param root string
---@param gradle_filter string  the `--tests` value (e.g. "pkg.Class.method")
---@param maven_filter string   the `-Dtest` value (e.g. "Class#method")
---@param label string
---@return nil
local function run_filtered(root, gradle_filter, maven_filter, label)
    local tool = buildtool.detect(root)
    if not tool then
        vim.notify("lvim-lang: no Gradle or Maven project found", vim.log.levels.WARN, TITLE)
        return
    end
    local cmd = buildtool.base(tool, root)
    if tool == "gradle" then
        vim.list_extend(cmd, { "test", "--tests", gradle_filter })
    else
        vim.list_extend(cmd, { "test", "-Dtest=" .. maven_filter })
    end
    runner.run("kotlin", { name = label, cmd = cmd, cwd = root, group = "Test", matcher = "generic" })
end

--- `:LvimLang test-func` — run the single test function under the cursor
--- (`--tests pkg.Class.method` / `-Dtest=Class#method`).
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local class, method = enclosing(ctx.bufnr)
    if not (class and method) then
        vim.notify("lvim-lang: cursor is not inside a test function", vim.log.levels.WARN, TITLE)
        return
    end
    local pkg = package_name(ctx.bufnr)
    run_filtered(
        ctx.root or root_of(ctx.bufnr),
        fqcn(pkg, class) .. "." .. method,
        class .. "#" .. method,
        "test " .. class .. "." .. method
    )
end

--- `:LvimLang test-file` — run every test in the current buffer's class
--- (`--tests pkg.Class` / `-Dtest=Class`).
---@param _args string[]
---@param ctx table
---@return nil
function M.file(_args, ctx)
    local class = select(1, enclosing(ctx.bufnr))
    if not class then
        -- Fall back to the file's basename (a Kotlin test class usually matches its file name).
        local name = vim.api.nvim_buf_get_name(ctx.bufnr)
        class = name ~= "" and vim.fn.fnamemodify(name, ":t:r") or nil
    end
    if not class then
        vim.notify("lvim-lang: no test class for this buffer", vim.log.levels.WARN, TITLE)
        return
    end
    local pkg = package_name(ctx.bufnr)
    run_filtered(ctx.root or root_of(ctx.bufnr), fqcn(pkg, class), class, "test " .. class)
end

return M
