-- lvim-lang.providers.ruby.test: RSpec test running — the whole suite, the current file, and the
-- example under the cursor. RSpec addresses examples by `file:line`, so the cursor example is found
-- with treesitter (the nearest enclosing `it` / `specify` / `example` / `scenario` call) and its
-- START line handed to rspec as `<file>:<line>`; a plain cursor-line fallback covers files without a
-- parser. Runs go through core.runner → lvim-tasks (Test group, `generic` matcher). Every run prefers
-- `bundle exec rspec` when the project has a Gemfile + bundler, else the direct `rspec` binary.
--
---@module "lvim-lang.providers.ruby.test"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

-- RSpec example DSL methods whose block the cursor may sit in (the ones a `<file>:<line>` filter
-- targets). Nested `describe`/`context` also accept a line, but examples are the useful granularity.
---@type table<string, boolean>
local EXAMPLE_METHODS = {
    it = true,
    specify = true,
    example = true,
    scenario = true,
    its = true,
}

local M = {}

--- The Ruby project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "Gemfile", "Rakefile", ".ruby-version", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The rspec command prefix for a root: `bundle exec rspec` when a Gemfile + bundler are present,
--- else the resolved `rspec` binary (or the bare name). Returned as an argv list.
---@param root string
---@return string[]
local function rspec_cmd(root)
    if vim.fn.filereadable(vim.fs.joinpath(root, "Gemfile")) == 1 then
        local bundle = toolchain.resolve("ruby", "bundle", root)
        if bundle then
            return { bundle, "exec", "rspec" }
        end
    end
    return { toolchain.resolve("ruby", "rspec", root) or "rspec" }
end

--- The 1-based START line of the RSpec example enclosing the cursor (treesitter): the nearest `call`
--- whose method is an example DSL method (`it` / `specify` / …). Falls back to the current cursor
--- line when no parser / no enclosing example — rspec then resolves the example containing that line.
---@param bufnr integer
---@return integer
function M.example_line(bufnr)
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return cursor_line
    end
    while node do
        if node:type() == "call" then
            local method = node:field("method")[1]
            local name = method and vim.treesitter.get_node_text(method, bufnr) or nil
            if name and EXAMPLE_METHODS[name] then
                return select(1, node:range()) + 1 -- range() is 0-based
            end
        end
        node = node:parent()
    end
    return cursor_line
end

--- Run an rspec argv (prefix + tail) for a root through lvim-tasks (Test group, `generic` matcher).
---@param root string
---@param tail string[]
---@param label string
---@return nil
local function run_rspec(root, tail, label)
    local cmd = rspec_cmd(root)
    vim.list_extend(cmd, tail)
    runner.run("ruby", { name = label, cmd = cmd, cwd = root, group = "Test", matcher = "generic" })
end

--- `:LvimLang test [args]` — run the whole RSpec suite (`bundle exec rspec`).
---@param args string[]
---@param ctx table
---@return nil
function M.suite(args, ctx)
    local root = ctx.root or root_of(ctx.bufnr)
    run_rspec(root, args, "rspec")
end

--- `:LvimLang test-file` — run every example in the current spec file (`rspec <file>`).
---@param _args string[]
---@param ctx table
---@return nil
function M.file(_args, ctx)
    local file = vim.api.nvim_buf_get_name(ctx.bufnr)
    if file == "" then
        vim.notify("lvim-lang: no file for this buffer", vim.log.levels.WARN, TITLE)
        return
    end
    run_rspec(ctx.root or root_of(ctx.bufnr), { file }, "rspec " .. vim.fs.basename(file))
end

--- `:LvimLang test-func` — run the RSpec example under the cursor (`rspec <file>:<line>`).
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local file = vim.api.nvim_buf_get_name(ctx.bufnr)
    if file == "" then
        vim.notify("lvim-lang: no file for this buffer", vim.log.levels.WARN, TITLE)
        return
    end
    local line = M.example_line(ctx.bufnr)
    run_rspec(ctx.root or root_of(ctx.bufnr), { file .. ":" .. line }, "rspec " .. vim.fs.basename(file) .. ":" .. line)
end

return M
