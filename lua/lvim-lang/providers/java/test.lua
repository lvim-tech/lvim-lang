-- lvim-lang.providers.java.test: JUnit test running — the whole suite, the current file, and the
-- test under the cursor. The cursor test is found with treesitter (the enclosing `method_declaration`
-- + its enclosing `class_declaration` + the file's `package` declaration) and addressed to the build
-- tool: Gradle filters with `--tests "<pkg>.<Class>.<method>"`, Maven with `-Dtest=<Class>#<method>`
-- (Surefire). Runs go through core.runner → lvim-tasks (Test group, `generic` matcher). Whole-suite
-- test running is `:LvimLang test` (see tasks.lua); this module adds the granular targets.
--
---@module "lvim-lang.providers.java.test"

local runner = require("lvim-lang.core.runner")
local buildtool = require("lvim-lang.providers.java.buildtool")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The Java project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, {
            "settings.gradle",
            "settings.gradle.kts",
            "build.gradle",
            "build.gradle.kts",
            "pom.xml",
            ".git",
        }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The buffer's `package …;` name via treesitter (a `package_declaration`'s identifier), or nil for
--- the default package.
---@param bufnr integer
---@return string|nil
local function package_name(bufnr)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "java")
    if not ok or not parser then
        return nil
    end
    local tree = (parser:parse() or {})[1]
    if not tree then
        return nil
    end
    for node in tree:root():iter_children() do
        if node:type() == "package_declaration" then
            for child in node:iter_children() do
                local t = child:type()
                if t == "scoped_identifier" or t == "identifier" then
                    return vim.treesitter.get_node_text(child, bufnr)
                end
            end
        end
    end
    return nil
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
            -- Keep walking so the OUTERMOST class wins (JUnit addresses by the top-level class).
            local n = node:field("name")[1]
            class = n and vim.treesitter.get_node_text(n, bufnr) or class
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
    runner.run("java", { name = label, cmd = cmd, cwd = root, group = "Test", matcher = "generic" })
end

--- `:LvimLang test-func` — run the single JUnit method under the cursor
--- (`--tests pkg.Class.method` / `-Dtest=Class#method`).
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local class, method = enclosing(ctx.bufnr)
    if not (class and method) then
        vim.notify("lvim-lang: cursor is not inside a test method", vim.log.levels.WARN, TITLE)
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

--- `:LvimLang test-file` — run every JUnit test in the current buffer's class
--- (`--tests pkg.Class` / `-Dtest=Class`).
---@param _args string[]
---@param ctx table
---@return nil
function M.file(_args, ctx)
    local class = select(1, enclosing(ctx.bufnr))
    if not class then
        -- Fall back to the file's basename (a top-level class matches its file name in Java).
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
