-- lvim-lang.providers.elixir.test: ExUnit test running — the whole suite, the current file, and the
-- test under the cursor. ExUnit addresses a test by `file:line`, so the cursor test is found with
-- treesitter (the nearest enclosing `test` / `describe` macro call) and its START line handed to
-- `mix test` as `<file>:<line>`; a plain cursor-line fallback covers files without a parser. Runs go
-- through core.runner → lvim-tasks (Test group, `generic` matcher). `mix` is resolved per project
-- through core.toolchain, and every run happens from the mix project root.
--
---@module "lvim-lang.providers.elixir.test"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

-- ExUnit macro calls whose block the cursor may sit in (the ones a `<file>:<line>` filter targets).
-- `describe` groups also accept a line; `test` is the useful leaf granularity.
---@type table<string, boolean>
local TEST_MACROS = {
    test = true,
    describe = true,
}

local M = {}

--- The Elixir project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "mix.exs", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The `mix test` command prefix for a root (the resolved `mix` binary, else the bare name), as an
--- argv list ending in `test`.
---@param root string
---@return string[]
local function mix_test_cmd(root)
    local mix = toolchain.resolve("elixir", "mix", root) or "mix"
    return { mix, "test" }
end

--- The 1-based START line of the ExUnit `test` / `describe` block enclosing the cursor (treesitter):
--- the nearest `call` whose target identifier is a test macro. Falls back to the current cursor line
--- when there is no parser / no enclosing test — `mix test` then resolves the block containing it.
---@param bufnr integer
---@return integer
function M.test_line(bufnr)
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return cursor_line
    end
    while node do
        if node:type() == "call" then
            local target = node:field("target")[1]
            local name = target and vim.treesitter.get_node_text(target, bufnr) or nil
            if name and TEST_MACROS[name] then
                return select(1, node:range()) + 1 -- range() is 0-based
            end
        end
        node = node:parent()
    end
    return cursor_line
end

--- Run a `mix test` argv (prefix + tail) for a root through lvim-tasks (Test group, `generic` matcher).
---@param root string
---@param tail string[]
---@param label string
---@return nil
local function run_test(root, tail, label)
    local cmd = mix_test_cmd(root)
    vim.list_extend(cmd, tail)
    runner.run("elixir", { name = label, cmd = cmd, cwd = root, group = "Test", matcher = "generic" })
end

--- `:LvimLang test [args]` — run the whole ExUnit suite (`mix test`).
---@param args string[]
---@param ctx table
---@return nil
function M.suite(args, ctx)
    run_test(ctx.root or root_of(ctx.bufnr), args, "mix test")
end

--- `:LvimLang test-file` — run every test in the current file (`mix test <file>`).
---@param _args string[]
---@param ctx table
---@return nil
function M.file(_args, ctx)
    local file = vim.api.nvim_buf_get_name(ctx.bufnr)
    if file == "" then
        vim.notify("lvim-lang: no file for this buffer", vim.log.levels.WARN, TITLE)
        return
    end
    run_test(ctx.root or root_of(ctx.bufnr), { file }, "mix test " .. vim.fs.basename(file))
end

--- `:LvimLang test-func` — run the ExUnit test under the cursor (`mix test <file>:<line>`).
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local file = vim.api.nvim_buf_get_name(ctx.bufnr)
    if file == "" then
        vim.notify("lvim-lang: no file for this buffer", vim.log.levels.WARN, TITLE)
        return
    end
    local line = M.test_line(ctx.bufnr)
    run_test(
        ctx.root or root_of(ctx.bufnr),
        { file .. ":" .. line },
        "mix test " .. vim.fs.basename(file) .. ":" .. line
    )
end

return M
