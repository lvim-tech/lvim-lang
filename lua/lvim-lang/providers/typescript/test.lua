-- lvim-lang.providers.typescript.test: JS/TS test running — the whole suite, the current file, the
-- test under the cursor, and a coverage overlay. The runner (vitest / jest) is detected from the
-- project (config files / devDependencies / the test script). The test under the cursor is found with
-- treesitter (the enclosing `it` / `test` / `describe` call's title) and run with `-t <title>`. Runs
-- go through core.runner → lvim-tasks (Test group, `typescript` matcher). Coverage runs the runner
-- with a JSON reporter, then paints the current buffer's covered / uncovered statements in the gutter
-- (own namespace, shared coverage highlights).
--
---@module "lvim-lang.providers.typescript.test"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")
local pm = require("lvim-lang.providers.typescript.pm")

local TITLE = { title = "lvim-lang" }
local NS = vim.api.nvim_create_namespace("lvim_lang_ts_coverage")

local M = {}

--- The JS/TS project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "package.json", "tsconfig.json", "jsconfig.json", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The test runner for a root: the pinned `test_runner` (unless "auto"), else detected — vitest
--- (config / devDependency / test script), jest (same), default vitest.
---@param root string
---@return "vitest"|"jest"
local function detect_runner(root)
    local pinned = (require("lvim-lang.config").providers.typescript or {}).test_runner
    if pinned == "vitest" or pinned == "jest" then
        return pinned
    end
    for _, name in ipairs({ "vitest.config.ts", "vitest.config.js", "vitest.config.mjs", "vitest.workspace.ts" }) do
        if vim.fn.filereadable(vim.fs.joinpath(root, name)) == 1 then
            return "vitest"
        end
    end
    for _, name in ipairs({ "jest.config.ts", "jest.config.js", "jest.config.mjs", "jest.config.json" }) do
        if vim.fn.filereadable(vim.fs.joinpath(root, name)) == 1 then
            return "jest"
        end
    end
    local pkg = pm.package_json(root) or {}
    local dev = pkg.devDependencies or {}
    local deps = pkg.dependencies or {}
    if dev.vitest or deps.vitest then
        return "vitest"
    end
    if dev.jest or deps.jest then
        return "jest"
    end
    local script = pkg.scripts and pkg.scripts.test or ""
    if type(script) == "string" and script:match("jest") then
        return "jest"
    end
    return "vitest"
end

--- The command that runs `runner` at `root`: the project-local binary, else `npx <runner>` (which
--- uses the local install when present and is universally available).
---@param root string
---@param runner_name string
---@return string[]
local function runner_cmd(root, runner_name)
    local bin = toolchain.resolve("typescript", runner_name, root)
    return bin and { bin } or { "npx", runner_name }
end

--- Run the test runner with `extra` argv at a root through lvim-tasks (Test group).
---@param root string
---@param runner_name string
---@param extra string[]
---@param name string
---@param hooks? table
---@return nil
local function run_runner(root, runner_name, extra, name, hooks)
    local cmd = runner_cmd(root, runner_name)
    vim.list_extend(cmd, extra)
    runner.run(
        "typescript",
        { name = name, cmd = cmd, cwd = root, group = "Test", matcher = "typescript", hooks = hooks }
    )
end

--- The title of the enclosing `it` / `test` / `describe` call under the cursor, via treesitter (the
--- first string argument of the call). Returns the unquoted title, or nil.
---@param bufnr integer
---@return string|nil
local function enclosing_title(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil
    end
    while node do
        if node:type() == "call_expression" then
            local fn = node:field("function")[1]
            local fname = fn and vim.treesitter.get_node_text(fn, bufnr) or ""
            -- `it` / `test` / `describe`, plus `.only` / `.each` / `.skip` variants (e.g. `it.only`).
            local base = fname:match("^([%a]+)") or ""
            if base == "it" or base == "test" or base == "describe" then
                local args = node:field("arguments")[1]
                if args then
                    for child in args:iter_children() do
                        if child:type() == "string" then
                            local text = vim.treesitter.get_node_text(child, bufnr)
                            return (text:gsub("^['\"`]", ""):gsub("['\"`]$", ""))
                        end
                    end
                end
            end
        end
        node = node:parent()
    end
    return nil
end

--- `:LvimLang test [args]` — run the whole suite (vitest run / jest).
---@param args string[]
---@param ctx table
---@return nil
function M.suite(args, ctx)
    local root = ctx.root or root_of(ctx.bufnr)
    local rn = detect_runner(root)
    local extra = rn == "vitest" and { "run" } or {}
    vim.list_extend(extra, args)
    run_runner(root, rn, extra, rn)
end

--- `:LvimLang test-file` — run the current buffer's file.
---@param _args string[]
---@param ctx table
---@return nil
function M.file(_args, ctx)
    local file = vim.api.nvim_buf_get_name(ctx.bufnr)
    if file == "" then
        vim.notify("lvim-lang: no file to test", vim.log.levels.WARN, TITLE)
        return
    end
    local root = root_of(ctx.bufnr)
    local rn = detect_runner(root)
    local extra = rn == "vitest" and { "run", file } or { file }
    run_runner(root, rn, extra, rn .. " " .. vim.fs.basename(file))
end

--- `:LvimLang test-func` — run the `it` / `test` under the cursor (`-t <title>`).
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local title = enclosing_title(ctx.bufnr)
    if not title then
        vim.notify("lvim-lang: cursor is not inside an it()/test()/describe() block", vim.log.levels.WARN, TITLE)
        return
    end
    local file = vim.api.nvim_buf_get_name(ctx.bufnr)
    local root = root_of(ctx.bufnr)
    local rn = detect_runner(root)
    local extra = rn == "vitest" and { "run", file, "-t", title } or { file, "-t", title }
    run_runner(root, rn, extra, rn .. " -t " .. title)
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

--- Paint an istanbul `coverage-final.json` onto the open buffers it covers: each statement is green
--- (hit) or red (missed) over its line range (own namespace, shared coverage highlights). Keys are
--- absolute paths.
---@param report string  path to the coverage-final.json
---@return integer  number of files painted
local function paint_coverage(report)
    local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(report), "\n"))
    if not ok or type(data) ~= "table" then
        return 0
    end
    local painted = 0
    for path, info in pairs(data) do
        local bufnr = buf_for_path(path)
        if bufnr and type(info) == "table" and type(info.statementMap) == "table" then
            for id, loc in pairs(info.statementMap) do
                local count = (info.s or {})[id] or 0
                local hl = (tonumber(count) or 0) > 0 and "LvimLangCoverageCovered" or "LvimLangCoverageUncovered"
                local s_line = loc.start and loc.start.line
                local e_line = (loc["end"] and loc["end"].line) or s_line
                if s_line then
                    for l = s_line, e_line do
                        pcall(
                            vim.api.nvim_buf_set_extmark,
                            bufnr,
                            NS,
                            l - 1,
                            0,
                            { sign_text = "▎", sign_hl_group = hl }
                        )
                    end
                end
            end
            painted = painted + 1
        end
    end
    return painted
end

--- `:LvimLang coverage [clear]` — run the test runner with a JSON coverage reporter, then paint the
--- covered / uncovered statements in the gutter. `coverage clear` removes the overlay.
---@param args string[]
---@param ctx table
---@return nil
function M.coverage(args, ctx)
    if args[1] == "clear" then
        M.clear(ctx.bufnr)
        return
    end
    local root = ctx.root or root_of(ctx.bufnr)
    local rn = detect_runner(root)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local report = vim.fs.joinpath(dir, "coverage-final.json")
    local extra = rn == "vitest"
            and { "run", "--coverage", "--coverage.reporter=json", "--coverage.reportsDirectory=" .. dir }
        or { "--coverage", "--coverageReporters=json", "--coverageDirectory=" .. dir }
    M.clear(ctx.bufnr)
    run_runner(root, rn, extra, rn .. " --coverage", {
        on_exit = function()
            vim.schedule(function()
                if vim.fn.filereadable(report) ~= 1 then
                    vim.notify(
                        "lvim-lang: no coverage report — is a coverage provider installed (e.g. @vitest/coverage-v8)?",
                        vim.log.levels.WARN,
                        TITLE
                    )
                    return
                end
                local n = paint_coverage(report)
                vim.notify(("lvim-lang: coverage painted (%d file(s))"):format(n), vim.log.levels.INFO, TITLE)
                pcall(vim.fn.delete, dir, "rf")
            end)
        end,
    })
end

return M
