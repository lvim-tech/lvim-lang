-- lvim-lang.providers.rust.test: Rust test running — the whole crate, the test under the cursor, and
-- the faster nextest runner. The test under the cursor is found with treesitter (the enclosing
-- function_item's name) and run with `cargo test <name>` (cargo filters by name substring). All
-- through core.runner → lvim-tasks (Test group, `rust` matcher). nextest is on-demand.
--
---@module "lvim-lang.providers.rust.test"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The Cargo crate root for the current buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "Cargo.toml", "Cargo.lock", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `cargo <argv…>` for a root through lvim-tasks (Test group, `rust` matcher).
---@param root string
---@param argv string[]
---@param name string
---@return nil
local function run_cargo(root, argv, name)
    local cargo = toolchain.resolve("rust", "cargo", root) or "cargo"
    local cmd = { cargo }
    vim.list_extend(cmd, argv)
    runner.run("rust", { name = name, cmd = cmd, cwd = root, group = "Test", matcher = "rust" })
end

--- The name of the function_item enclosing the cursor (treesitter), or nil. `cargo test <name>`
--- then runs every test whose path contains it — enough to run a single `#[test]` fn.
---@param bufnr integer
---@return string|nil
local function enclosing_fn(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil
    end
    while node do
        if node:type() == "function_item" then
            local name_node = node:field("name")[1]
            return name_node and vim.treesitter.get_node_text(name_node, bufnr) or nil
        end
        node = node:parent()
    end
    return nil
end

--- `:LvimLang test-func` — run the `#[test]` function under the cursor (`cargo test <name>`).
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local name = enclosing_fn(ctx.bufnr)
    if not name then
        vim.notify("lvim-lang: cursor is not inside a function", vim.log.levels.WARN, TITLE)
        return
    end
    run_cargo(root_of(ctx.bufnr), { "test", name, "--", "--nocapture" }, "cargo test " .. name)
end

--- `:LvimLang nextest [args]` — `cargo nextest run` (the faster test runner). On-demand: nextest is a
--- cargo-install / mason tool, not part of the toolchain — a missing one is reported with an install hint.
---@param args string[]
---@param ctx table
---@return nil
function M.nextest(args, ctx)
    if vim.fn.executable("cargo-nextest") ~= 1 then
        vim.notify(
            "lvim-lang: cargo-nextest not found — install it with `cargo install cargo-nextest` (or the mason registry)",
            vim.log.levels.WARN,
            TITLE
        )
        return
    end
    local argv = { "nextest", "run" }
    vim.list_extend(argv, args)
    run_cargo(ctx.root or root_of(ctx.bufnr), argv, "cargo nextest")
end

return M
