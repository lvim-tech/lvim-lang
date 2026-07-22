-- lvim-lang.providers.rust.tasks: one-shot `cargo` commands run through lvim-tasks.
-- build / run / test / check / clippy / fmt are fire-and-collect commands, so they go through
-- core.runner → lvim-tasks with the built-in `rust` problem matcher (rustc's `error[E…]: msg` +
-- ` --> file:line:col`) routing diagnostics to the quickfix list. Extra command-line args are
-- appended (e.g. `:LvimLang build --release`, `:LvimLang test -- --nocapture`).
--
---@module "lvim-lang.providers.rust.tasks"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local M = {}

--- Resolve the Cargo project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "Cargo.toml", "Cargo.lock", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `cargo <argv…>` for a root through lvim-tasks (with the `rust` problem matcher). `env`
--- (optional) is passed to the task process.
---@param root string
---@param argv string[]
---@param name string
---@param group string
---@param env? table<string, string>
---@return nil
local function run_cargo(root, argv, name, group, env)
    local cargo = toolchain.resolve("rust", "cargo", root) or "cargo"
    local cmd = { cargo }
    vim.list_extend(cmd, argv)
    runner.run("rust", { name = name, cmd = cmd, cwd = root, group = group, matcher = "rust", env = env })
end

--- `:LvimLang build [args]` — `cargo build`.
---@param args string[]
---@param ctx table
---@return nil
function M.build(args, ctx)
    local argv = { "build" }
    vim.list_extend(argv, args)
    run_cargo(ctx.root, argv, "cargo build", "Build")
end

--- `:LvimLang run [args]` — `cargo run`. (The active run config's args/env/features apply in R8.)
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    local rc = require("lvim-lang.core.runcfg").active(ctx.root)
    local argv, env = { "run" }, nil
    if rc then
        vim.list_extend(argv, rc.cargo_flags or {})
        if rc.features then
            argv[#argv + 1] = "--features"
            argv[#argv + 1] = type(rc.features) == "table" and table.concat(rc.features, ",") or rc.features
        end
        if rc.bin then
            argv[#argv + 1] = "--bin"
            argv[#argv + 1] = rc.bin
        end
        if #(rc.args or {}) > 0 then
            argv[#argv + 1] = "--"
            vim.list_extend(argv, rc.args)
        end
        vim.list_extend(argv, args)
        env = rc.env
    else
        vim.list_extend(argv, args)
    end
    run_cargo(ctx.root, argv, "cargo run", "Run", env)
end

--- `:LvimLang test [args]` — `cargo test`. (Test-under-cursor / nextest come in R5.)
---@param args string[]
---@param ctx table
---@return nil
function M.test(args, ctx)
    local argv = { "test" }
    vim.list_extend(argv, args)
    run_cargo(ctx.root, argv, "cargo test", "Test")
end

--- `:LvimLang check [args]` — `cargo check`.
---@param args string[]
---@param ctx table
---@return nil
function M.check(args, ctx)
    local argv = { "check" }
    vim.list_extend(argv, args)
    run_cargo(ctx.root, argv, "cargo check", "Build")
end

--- `:LvimLang clippy [args]` — `cargo clippy` (the richer lint set; RA runs it on save too).
---@param args string[]
---@param ctx table
---@return nil
function M.clippy(args, ctx)
    local argv = { "clippy" }
    vim.list_extend(argv, #args > 0 and args or { "--all-targets" })
    run_cargo(ctx.root, argv, "cargo clippy", "Lint")
end

--- `:LvimLang fmt [args]` — `cargo fmt` (rustfmt over the whole crate).
---@param args string[]
---@param ctx table
---@return nil
function M.fmt(args, ctx)
    local argv = { "fmt" }
    vim.list_extend(argv, args)
    -- fmt rewrites files on disk; core.runner's :checktime on exit reloads open buffers.
    run_cargo(ctx.root, argv, "cargo fmt", "Format")
end

--- The buffer's project root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
