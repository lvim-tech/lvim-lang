-- lvim-lang.providers.clojure.test: clojure.test running — the whole suite (see tasks.lua), the
-- current file's namespace, and the `deftest` under the cursor. The cursor test is found with
-- treesitter (the enclosing `(deftest <name> …)` list) plus the file's `(ns <namespace> …)` form, and
-- addressed to the build tool's test runner: Leiningen filters with `lein test :only <ns>/<test>`
-- (file: `lein test <ns>`); the Clojure CLI, when its test alias is an EXEC runner (`-X:test`, the
-- Cognitect test-runner convention), filters with `:vars '[<ns>/<test>]'` (file: `:nses '[<ns>]'`).
-- When the CLI test alias is a `-M` main (whose selector syntax is runner-specific and unknown) or the
-- tool is Boot, per-test filtering is not possible, so the run falls back to the whole suite with a
-- notice. Runs go through core.runner → lvim-tasks (Test group, `generic` matcher).
--
---@module "lvim-lang.providers.clojure.test"

local config = require("lvim-lang.config")
local runner = require("lvim-lang.core.runner")
local buildtool = require("lvim-lang.providers.clojure.buildtool")

local TITLE = { title = "lvim-lang" }

-- The definition forms that declare a test (their second symbol is the test name).
---@type table<string, boolean>
local TEST_FORMS = { deftest = true, ["deftest-"] = true, defspec = true }

local M = {}

--- The clojure provider's `tasks.clj` config block (alias / exec-vs-main), with defaults.
---@return { test_alias: string, test_exec: boolean }
local function clj_opts()
    local t = ((config.providers.clojure or {}).tasks or {}).clj or {}
    return { test_alias = t.test_alias or "test", test_exec = t.test_exec ~= false }
end

--- Resolve the Clojure project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "deps.edn", "project.clj", "build.boot", "shadow-cljs.edn", ".git" })
            or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The ordered `sym_lit` (symbol) texts directly inside a list node — e.g. `(deftest foo …)` yields
--- { "deftest", "foo", … }. Non-symbol children (keywords, strings, nested lists) are skipped.
---@param list_node TSNode
---@param bufnr integer
---@return string[]
local function list_symbols(list_node, bufnr)
    local syms = {}
    for child in list_node:iter_children() do
        if child:type() == "sym_lit" then
            syms[#syms + 1] = vim.treesitter.get_node_text(child, bufnr)
        end
    end
    return syms
end

--- The buffer's namespace via treesitter — the second symbol of the top-level `(ns <namespace> …)`
--- form — or nil when there is none.
---@param bufnr integer
---@return string|nil
local function namespace(bufnr)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "clojure")
    if not ok or not parser then
        return nil
    end
    local tree = (parser:parse() or {})[1]
    if not tree then
        return nil
    end
    for node in tree:root():iter_children() do
        if node:type() == "list_lit" then
            local syms = list_symbols(node, bufnr)
            if syms[1] == "ns" and syms[2] then
                return syms[2]
            end
        end
    end
    return nil
end

--- The name of the `deftest`/`defspec` enclosing the cursor, via treesitter (walk up to a list whose
--- first symbol is a test form; its second symbol is the test name), or nil.
---@param bufnr integer
---@return string|nil
local function enclosing_test(bufnr)
    -- Ensure the tree is parsed before locating the cursor node — on a buffer treesitter highlighting
    -- has not yet touched, get_node would otherwise see no tree and miss the enclosing form.
    local ok_p, parser = pcall(vim.treesitter.get_parser, bufnr, "clojure")
    if not ok_p or not parser then
        return nil
    end
    parser:parse()
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil
    end
    while node do
        if node:type() == "list_lit" then
            local syms = list_symbols(node, bufnr)
            if syms[1] and TEST_FORMS[syms[1]] and syms[2] then
                return syms[2]
            end
        end
        node = node:parent()
    end
    return nil
end

--- Run a Clojure test command at `root` through lvim-tasks (Test group, `generic` matcher).
---@param root string
---@param tail string[]  the tool-specific argv tail
---@param label string
---@return nil
local function run(root, tail, label)
    local cmd = buildtool.base(buildtool.detect(root) or "clj", root)
    vim.list_extend(cmd, tail)
    runner.run("clojure", { name = label, cmd = cmd, cwd = root, group = "Test", matcher = "generic" })
end

--- The whole-suite test tail for a tool (used as the fallback when filtering is not possible).
---@param tool "clj"|"lein"|"boot"
---@return string[]
local function suite_tail(tool)
    if tool == "clj" then
        local c = clj_opts()
        return { (c.test_exec and "-X:" or "-M:") .. c.test_alias }
    end
    return { "test" }
end

--- `:LvimLang test-func` — run the single `deftest` under the cursor when the tool can filter to it,
--- else the whole suite with a notice.
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local test = enclosing_test(ctx.bufnr)
    if not test then
        vim.notify("lvim-lang: cursor is not inside a deftest", vim.log.levels.WARN, TITLE)
        return
    end
    local ns = namespace(ctx.bufnr)
    if not ns then
        vim.notify("lvim-lang: no (ns …) form in this buffer — cannot address the test", vim.log.levels.WARN, TITLE)
        return
    end
    local root = ctx.root or root_of(ctx.bufnr)
    local tool = buildtool.detect(root) or "clj"
    local var = ns .. "/" .. test
    if tool == "lein" then
        run(root, { "test", ":only", var }, "lein test " .. var)
    elseif tool == "clj" and clj_opts().test_exec then
        -- Cognitect test-runner exec: `-X:<alias> :vars '[ns/test]'`.
        run(root, { "-X:" .. clj_opts().test_alias, ":vars", "[" .. var .. "]" }, "clojure test " .. var)
    else
        vim.notify(
            ("lvim-lang: per-test filtering needs Leiningen or an exec (-X) Clojure test alias — running the whole suite for %s"):format(
                var
            ),
            vim.log.levels.INFO,
            TITLE
        )
        run(root, suite_tail(tool), "clojure test (suite)")
    end
end

--- `:LvimLang test-file` — run every test in the current buffer's namespace when the tool can filter
--- to it, else the whole suite with a notice.
---@param _args string[]
---@param ctx table
---@return nil
function M.file(_args, ctx)
    local ns = namespace(ctx.bufnr)
    if not ns then
        vim.notify("lvim-lang: no (ns …) form in this buffer", vim.log.levels.WARN, TITLE)
        return
    end
    local root = ctx.root or root_of(ctx.bufnr)
    local tool = buildtool.detect(root) or "clj"
    if tool == "lein" then
        run(root, { "test", ns }, "lein test " .. ns)
    elseif tool == "clj" and clj_opts().test_exec then
        run(root, { "-X:" .. clj_opts().test_alias, ":nses", "[" .. ns .. "]" }, "clojure test " .. ns)
    else
        vim.notify(
            ("lvim-lang: per-namespace filtering needs Leiningen or an exec (-X) Clojure test alias — running the whole suite for %s"):format(
                ns
            ),
            vim.log.levels.INFO,
            TITLE
        )
        run(root, suite_tail(tool), "clojure test (suite)")
    end
end

return M
