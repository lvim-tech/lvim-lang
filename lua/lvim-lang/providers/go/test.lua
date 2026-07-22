-- lvim-lang.providers.go.test: Go test running — the whole package, the file, the test under the
-- cursor, and a coverage overlay. Test funcs are found with treesitter (the enclosing
-- Test/Benchmark/Fuzz/Example function), so `test-func` runs exactly one. Runs go through
-- core.runner → lvim-tasks (Test group, `go` matcher). Coverage runs `go test -coverprofile`, then
-- paints the current buffer's covered / uncovered lines in the gutter (own namespace, self-themed).
--
---@module "lvim-lang.providers.go.test"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }
local NS = vim.api.nvim_create_namespace("lvim_lang_go_coverage")

local M = {}

--- The `go` binary for a root.
---@param root string
---@return string
local function go_bin(root)
    return toolchain.resolve("go", "go", root) or "go"
end

--- The directory of the current buffer's file (the Go package to test), or cwd.
---@return string
local function buffer_pkg_dir()
    local name = vim.api.nvim_buf_get_name(0)
    return name ~= "" and vim.fs.dirname(name) or (vim.uv.cwd() or ".")
end

--- The enclosing Go test-like function at the cursor (Test / Benchmark / Fuzz / Example), via
--- treesitter. Returns the name and whether it is a benchmark (which uses -bench, not -run).
---@param bufnr integer
---@return string|nil name, boolean is_bench
local function enclosing_test(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil, false
    end
    while node do
        if node:type() == "function_declaration" then
            local name_node = node:field("name")[1]
            if name_node then
                local name = vim.treesitter.get_node_text(name_node, bufnr)
                if name:match("^Test") or name:match("^Benchmark") or name:match("^Fuzz") or name:match("^Example") then
                    return name, name:match("^Benchmark") ~= nil
                end
            end
            return nil, false -- inside a non-test function
        end
        node = node:parent()
    end
    return nil, false
end

--- Run `go test <argv…>` at cwd through lvim-tasks (Test group, `go` matcher).
---@param cwd string
---@param argv string[]
---@param name string
---@param hooks? table
---@return nil
local function run_test(cwd, argv, name, hooks)
    local cmd = { go_bin(cwd) }
    vim.list_extend(cmd, argv)
    runner.run("go", { name = name, cmd = cmd, cwd = cwd, group = "Test", matcher = "go", hooks = hooks })
end

--- `:LvimLang test-func` — run the single Test/Benchmark/Fuzz/Example function under the cursor.
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local name, is_bench = enclosing_test(ctx.bufnr)
    if not name then
        vim.notify("lvim-lang: cursor is not inside a Test/Benchmark/Fuzz/Example function", vim.log.levels.WARN, TITLE)
        return
    end
    local dir = buffer_pkg_dir()
    local argv = is_bench and { "test", "-run", "^$", "-bench", "^" .. name .. "$", "-v", "." }
        or { "test", "-run", "^" .. name .. "$", "-v", "." }
    run_test(dir, argv, "go test " .. name)
end

--- `:LvimLang test-file` — run the tests in the current buffer's package.
---@param _args string[]
---@param _ctx table
---@return nil
function M.file(_args, _ctx)
    run_test(buffer_pkg_dir(), { "test", "-v", "." }, "go test (file package)")
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

--- Paint a coverprofile onto the open buffers it covers: each covered line gets a green gutter mark,
--- each uncovered line a red one (own namespace, self-themed). Coverage is run for ONE package
--- (cwd = `dir`), so every profile file lives in `dir` and maps by basename.
---@param profile string  path to the coverprofile file
---@param dir string      the package directory the coverage ran in
---@return integer  number of extmark blocks placed
local function paint_coverage(profile, dir)
    local lines = vim.fn.readfile(profile)
    if type(lines) ~= "table" then
        return 0
    end
    local buf_cache, marked = {}, 0
    for _, line in ipairs(lines) do
        -- format: <path>:<sLine>.<sCol>,<eLine>.<eCol> <numStmt> <count>
        local path, s_line, e_line, count = line:match("^(.-):(%d+)%.%d+,(%d+)%.%d+%s+%d+%s+(%d+)$")
        if path then
            local abspath = vim.fs.joinpath(dir, vim.fs.basename(path))
            if buf_cache[abspath] == nil then
                buf_cache[abspath] = buf_for_path(abspath) or false
            end
            local bufnr = buf_cache[abspath]
            if bufnr then
                local hl = tonumber(count) > 0 and "LvimLangCoverageCovered" or "LvimLangCoverageUncovered"
                for l = tonumber(s_line), tonumber(e_line) do
                    pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, l - 1, 0, { sign_text = "▎", sign_hl_group = hl })
                end
                marked = marked + 1
            end
        end
    end
    return marked
end

--- `:LvimLang coverage [clear]` — run `go test -coverprofile` for the file's package, then paint the
--- covered / uncovered lines in the gutter. `coverage clear` removes the overlay.
---@param args string[]
---@param ctx table
---@return nil
function M.coverage(args, ctx)
    if args[1] == "clear" then
        M.clear(ctx.bufnr)
        return
    end
    local dir = buffer_pkg_dir()
    local profile = vim.fn.tempname()
    M.clear(ctx.bufnr)
    run_test(dir, { "test", "-covermode=atomic", "-coverprofile=" .. profile, "." }, "go test -cover", {
        on_exit = function()
            vim.schedule(function()
                if vim.fn.filereadable(profile) == 1 then
                    local n = paint_coverage(profile, dir)
                    vim.notify(("lvim-lang: coverage painted (%d block(s))"):format(n), vim.log.levels.INFO, TITLE)
                    pcall(vim.fn.delete, profile)
                end
            end)
        end,
    })
end

return M
