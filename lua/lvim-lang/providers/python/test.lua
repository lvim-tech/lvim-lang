-- lvim-lang.providers.python.test: Python test running — the whole suite, the current file, the test
-- under the cursor, unittest, and a coverage overlay. The test under the cursor is found with
-- treesitter (the enclosing `def test_*`, plus any enclosing `class Test*`) and addressed as a
-- pytest node id (`path::Class::test_name`). Runs go through core.runner → lvim-tasks (Test group,
-- `pytest` matcher). Coverage runs `coverage run -m pytest`, then `coverage json`, then paints the
-- current buffer's executed / missing lines in the gutter (own namespace, shared coverage highlights).
--
---@module "lvim-lang.providers.python.test"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }
local NS = vim.api.nvim_create_namespace("lvim_lang_python_coverage")

local M = {}

--- The venv interpreter for a root (else `python3`).
---@param root string
---@return string
local function python_bin(root)
    return toolchain.resolve("python", "python", root) or "python3"
end

--- The Python project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "pyproject.toml", "setup.py", "setup.cfg", "pytest.ini", "Pipfile", ".git" })
            or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `python -m <argv…>` at a root through lvim-tasks (Test group, `pytest` matcher).
---@param root string
---@param argv string[]
---@param name string
---@param hooks? table
---@return nil
local function run_pytest(root, argv, name, hooks)
    local cmd = { python_bin(root) }
    vim.list_extend(cmd, argv)
    runner.run("python", { name = name, cmd = cmd, cwd = root, group = "Test", matcher = "pytest", hooks = hooks })
end

--- The enclosing pytest node under the cursor: the `def test_*` function and any enclosing
--- `class Test*`, via treesitter. Returns the function name and the class name (or nil).
---@param bufnr integer
---@return string|nil func, string|nil class
local function enclosing_test(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil, nil
    end
    local func, class
    while node do
        local t = node:type()
        if t == "function_definition" and not func then
            local n = node:field("name")[1]
            local name = n and vim.treesitter.get_node_text(n, bufnr)
            if name and name:match("^test") then
                func = name
            end
        elseif t == "class_definition" and not class then
            local n = node:field("name")[1]
            class = n and vim.treesitter.get_node_text(n, bufnr) or nil
        end
        node = node:parent()
    end
    return func, class
end

--- `:LvimLang test [args]` — `pytest` over the whole suite (from the project root).
---@param args string[]
---@param ctx table
---@return nil
function M.suite(args, ctx)
    local argv = { "-m", "pytest" }
    vim.list_extend(argv, args)
    run_pytest(ctx.root or root_of(ctx.bufnr), argv, "pytest")
end

--- `:LvimLang test-file` — `pytest` over the current buffer's file.
---@param _args string[]
---@param ctx table
---@return nil
function M.file(_args, ctx)
    local file = vim.api.nvim_buf_get_name(ctx.bufnr)
    if file == "" then
        vim.notify("lvim-lang: no file to test", vim.log.levels.WARN, TITLE)
        return
    end
    run_pytest(root_of(ctx.bufnr), { "-m", "pytest", file, "-v" }, "pytest " .. vim.fs.basename(file))
end

--- `:LvimLang test-func` — run the single `def test_*` under the cursor as a pytest node id
--- (`file::[Class::]test_name`).
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local func, class = enclosing_test(ctx.bufnr)
    if not func then
        vim.notify("lvim-lang: cursor is not inside a `def test_*` function", vim.log.levels.WARN, TITLE)
        return
    end
    local file = vim.api.nvim_buf_get_name(ctx.bufnr)
    if file == "" then
        return
    end
    local node = class and (file .. "::" .. class .. "::" .. func) or (file .. "::" .. func)
    run_pytest(root_of(ctx.bufnr), { "-m", "pytest", node, "-v" }, "pytest " .. func)
end

--- `:LvimLang unittest [args]` — `python -m unittest` (discovery by default, or the given target,
--- e.g. `pkg.tests.TestCase.test_method`). The alternative to pytest for stdlib-only suites.
---@param args string[]
---@param ctx table
---@return nil
function M.unittest(args, ctx)
    local argv = { "-m", "unittest" }
    vim.list_extend(argv, #args > 0 and args or { "discover" })
    run_pytest(ctx.root or root_of(ctx.bufnr), argv, "unittest")
end

--- Clear the coverage overlay from a buffer.
---@param bufnr? integer
---@return nil
function M.clear(bufnr)
    vim.api.nvim_buf_clear_namespace(bufnr or 0, NS, 0, -1)
end

--- The open buffer for an absolute path, or nil (compared normalized).
---@param abspath string
---@return integer|nil
local function buf_for_path(abspath)
    local want = vim.fs.normalize(abspath)
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
        local n = vim.api.nvim_buf_get_name(b)
        if n ~= "" and vim.fs.normalize(n) == want then
            return b
        end
    end
    return nil
end

--- Paint a `coverage json` report onto the open buffers it covers: each executed line gets a green
--- gutter mark, each missing line a red one (own namespace, shared coverage highlights). Paths in
--- the report are relative to `root`.
---@param report string  path to the coverage json file
---@param root string    the directory coverage ran in
---@return integer  number of files painted
local function paint_coverage(report, root)
    local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(report), "\n"))
    if not ok or type(data) ~= "table" or type(data.files) ~= "table" then
        return 0
    end
    local painted = 0
    for path, info in pairs(data.files) do
        local abspath = vim.fs.normalize(vim.fs.joinpath(root, path))
        local bufnr = buf_for_path(abspath)
        if bufnr then
            for _, l in ipairs(info.executed_lines or {}) do
                pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, l - 1, 0, {
                    sign_text = "▎",
                    sign_hl_group = "LvimLangCoverageCovered",
                })
            end
            for _, l in ipairs(info.missing_lines or {}) do
                pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, l - 1, 0, {
                    sign_text = "▎",
                    sign_hl_group = "LvimLangCoverageUncovered",
                })
            end
            painted = painted + 1
        end
    end
    return painted
end

--- `:LvimLang coverage [clear]` — run `coverage run -m pytest`, then `coverage json`, then paint the
--- executed / missing lines in the gutter. Needs `coverage` importable in the interpreter.
--- `coverage clear` removes the overlay.
---@param args string[]
---@param ctx table
---@return nil
function M.coverage(args, ctx)
    if args[1] == "clear" then
        M.clear(ctx.bufnr)
        return
    end
    local root = ctx.root or root_of(ctx.bufnr)
    local py = python_bin(root)
    local report = vim.fn.tempname() .. ".json"
    M.clear(ctx.bufnr)
    run_pytest(root, { "-m", "coverage", "run", "-m", "pytest" }, "coverage run -m pytest", {
        on_exit = function()
            vim.schedule(function()
                -- Second step: export the JSON report, then paint. Run off the task panel (vim.system).
                vim.system({ py, "-m", "coverage", "json", "-o", report }, { cwd = root }, function(res)
                    vim.schedule(function()
                        if res.code ~= 0 or vim.fn.filereadable(report) ~= 1 then
                            vim.notify(
                                "lvim-lang: `coverage json` failed — is `coverage` installed in the interpreter?",
                                vim.log.levels.WARN,
                                TITLE
                            )
                            return
                        end
                        local n = paint_coverage(report, root)
                        vim.notify(("lvim-lang: coverage painted (%d file(s))"):format(n), vim.log.levels.INFO, TITLE)
                        pcall(vim.fn.delete, report)
                    end)
                end)
            end)
        end,
    })
end

return M
