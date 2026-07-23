-- lvim-lang.providers.swift.tasks: one-shot `swift` commands run through lvim-tasks.
-- build / run / test / clean are fire-and-collect commands, so they go through core.runner →
-- lvim-tasks with the `gcc` problem matcher — the Swift compiler emits LLVM/clang-style diagnostics
-- (`file.swift:line:col: error: message`), so the shared gcc errorformat routes them to the quickfix
-- list unchanged. `fmt` runs swiftformat over the whole package (it rewrites files on disk; the
-- runner's :checktime on exit reloads open buffers). Extra command-line args are appended
-- (`:LvimLang build -c release`, `:LvimLang test --filter MyTests`).
--
---@module "lvim-lang.providers.swift.tasks"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local M = {}

--- Resolve the SwiftPM package root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "Package.swift", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `swift <argv…>` for a root through lvim-tasks (with the `gcc` matcher — Swift shares the
--- clang diagnostic format). `env` (optional) is passed to the task process.
---@param root string
---@param argv string[]
---@param name string
---@param group string
---@param env? table<string, string>
---@return nil
local function run_swift(root, argv, name, group, env)
    local swift = toolchain.resolve("swift", "swift", root) or "swift"
    local cmd = { swift }
    vim.list_extend(cmd, argv)
    runner.run("swift", { name = name, cmd = cmd, cwd = root, group = group, matcher = "gcc", env = env })
end

--- `:LvimLang build [args]` — `swift build`.
---@param args string[]
---@param ctx table
---@return nil
function M.build(args, ctx)
    local argv = { "build" }
    vim.list_extend(argv, args)
    run_swift(ctx.root, argv, "swift build", "Build")
end

--- `:LvimLang run [args]` — `swift run` (+ the active run config's product / args / env).
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    local rc = require("lvim-lang.core.runcfg").active(ctx.root)
    local argv, env = { "run" }, nil
    if rc then
        vim.list_extend(argv, rc.swift_flags or {})
        -- The product / executable target to run (SwiftPM: `swift run <product> [args]`).
        if rc.product or rc.bin then
            argv[#argv + 1] = rc.product or rc.bin
        end
        if #(rc.args or {}) > 0 then
            vim.list_extend(argv, rc.args)
        end
        vim.list_extend(argv, args)
        env = rc.env
    else
        vim.list_extend(argv, args)
    end
    run_swift(ctx.root, argv, "swift run", "Run", env)
end

--- `:LvimLang test [args]` — `swift test`. (Test-under-cursor is `:LvimLang test-func`.)
---@param args string[]
---@param ctx table
---@return nil
function M.test(args, ctx)
    local argv = { "test" }
    vim.list_extend(argv, args)
    run_swift(ctx.root, argv, "swift test", "Test")
end

--- `:LvimLang clean [args]` — `swift package clean` (drop the .build artifacts).
---@param args string[]
---@param ctx table
---@return nil
function M.clean(args, ctx)
    local argv = { "package", "clean" }
    vim.list_extend(argv, args)
    run_swift(ctx.root, argv, "swift package clean", "Build")
end

--- `:LvimLang fmt [args]` — swiftformat over the whole package (rewrites files on disk; the runner's
--- :checktime on exit reloads open buffers). Resolves swiftformat through the toolchain (explicit /
--- mason / PATH); a missing one is reported with an install hint.
---@param args string[]
---@param ctx table
---@return nil
function M.fmt(args, ctx)
    local root = ctx.root or resolve_root()
    local swiftformat = toolchain.resolve("swift", "swiftformat", root)
    if not swiftformat then
        vim.notify(
            "lvim-lang: swiftformat not found — install it from the mason registry (or set providers.swift.swiftformat_path)",
            vim.log.levels.WARN,
            { title = "lvim-lang" }
        )
        return
    end
    local cmd = { swiftformat }
    vim.list_extend(cmd, #args > 0 and args or { "." })
    runner.run("swift", { name = "swiftformat", cmd = cmd, cwd = root, group = "Format" })
end

--- The buffer's package root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
