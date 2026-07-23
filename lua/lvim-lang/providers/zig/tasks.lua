-- lvim-lang.providers.zig.tasks: one-shot `zig` commands run through lvim-tasks.
-- build / run / test / fmt are fire-and-collect commands, so they go through core.runner →
-- lvim-tasks with the built-in `gcc` problem matcher (Zig emits the exact gcc/clang shape,
-- `file:line:col: error: msg`, so gcc routes its diagnostics to the quickfix list — no separate
-- matcher needed). Every command adapts to the project SHAPE at run time:
--   * build.zig present → the build system: `zig build`, `zig build run`, `zig build test`.
--   * no build.zig      → single file: `zig build-exe <file>`, `zig run <file>`, `zig test <file>`.
-- `zig fmt` is the FORMATTER — it ships inside the same `zig` binary (there is no separate tool);
-- `:LvimLang fmt` runs `zig fmt` over the project (or the file for a single-file buffer). Extra
-- command-line args are appended (e.g. `:LvimLang build -Doptimize=ReleaseFast`).
--
---@module "lvim-lang.providers.zig.tasks"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local M = {}

--- Resolve the Zig project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "build.zig", "build.zig.zon", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Whether `root` is a `zig build` project (a build.zig at the root).
---@param root string
---@return boolean
local function has_build_zig(root)
    return vim.fn.filereadable(root .. "/build.zig") == 1
end

--- The resolved `zig` binary for a root (explicit / version manager / PATH), else the bare name.
---@param root string
---@return string
local function zig_bin(root)
    return toolchain.resolve("zig", "zig", root) or "zig"
end

--- Run `zig <argv…>` for a root through lvim-tasks (with the `gcc` problem matcher). `env`
--- (optional) is passed to the task process; `hooks` (optional) chain follow-up tasks.
---@param root string
---@param argv string[]
---@param name string
---@param group string
---@param env? table<string, string>
---@param hooks? table
---@return nil
local function run_zig(root, argv, name, group, env, hooks)
    local cmd = { zig_bin(root) }
    vim.list_extend(cmd, argv)
    runner.run("zig", { name = name, cmd = cmd, cwd = root, group = group, matcher = "gcc", env = env, hooks = hooks })
end

--- The current buffer's file path (""/nil-safe), for the single-file (no build.zig) commands.
---@param ctx table
---@return string|nil
local function buffer_file(ctx)
    local buf = ctx.bufnr or vim.api.nvim_get_current_buf()
    local file = vim.api.nvim_buf_get_name(buf)
    return file ~= "" and file or nil
end

--- `:LvimLang build [args]` — `zig build` (build.zig project) or `zig build-exe <file>` (single
--- file, output into the lvim-lang cache dir).
---@param args string[]
---@param ctx table
---@return nil
function M.build(args, ctx)
    local root = ctx.root or resolve_root()
    if has_build_zig(root) then
        local argv = { "build" }
        vim.list_extend(argv, args)
        run_zig(root, argv, "zig build", "Build")
        return
    end
    local file = buffer_file(ctx)
    if not file then
        vim.notify("lvim-lang: no build.zig and no file to compile", vim.log.levels.WARN, { title = "lvim-lang" })
        return
    end
    local cache = vim.fs.normalize(vim.fn.stdpath("cache") .. "/lvim-lang")
    if vim.fn.isdirectory(cache) == 0 then
        pcall(vim.fn.mkdir, cache, "p")
    end
    local out = cache .. "/" .. vim.fn.fnamemodify(file, ":t:r")
    local argv = { "build-exe", file, "-femit-bin=" .. out }
    vim.list_extend(argv, args)
    run_zig(vim.fs.dirname(file), argv, "zig build-exe " .. vim.fs.basename(file), "Build")
end

--- `:LvimLang run [args]` — `zig build run` (build.zig project, + active run-config args/env) or
--- `zig run <file>` (single file). A run config supplies extra args and env.
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    local root = ctx.root or resolve_root()
    local rc = require("lvim-lang.core.runcfg").active(root)
    if has_build_zig(root) then
        -- `zig build run` runs the project's "run" step. Run-config `zig_flags` go BEFORE `--`; the
        -- program's own `args` go AFTER `--` (zig forwards them to the executable).
        local argv = { "build", "run" }
        if rc then
            vim.list_extend(argv, rc.zig_flags or {})
        end
        vim.list_extend(argv, args)
        if rc and #(rc.args or {}) > 0 then
            argv[#argv + 1] = "--"
            vim.list_extend(argv, rc.args)
        end
        run_zig(root, argv, "zig build run", "Run", rc and rc.env or nil)
        return
    end
    local file = buffer_file(ctx)
    if not file then
        vim.notify("lvim-lang: no build.zig and no file to run", vim.log.levels.WARN, { title = "lvim-lang" })
        return
    end
    local argv = { "run", file }
    if rc then
        vim.list_extend(argv, rc.zig_flags or {})
    end
    vim.list_extend(argv, args)
    if rc and #(rc.args or {}) > 0 then
        argv[#argv + 1] = "--"
        vim.list_extend(argv, rc.args)
    end
    run_zig(vim.fs.dirname(file), argv, "zig run " .. vim.fs.basename(file), "Run", rc and rc.env or nil)
end

--- `:LvimLang test [args]` — `zig build test` (build.zig project) or `zig test <file>` (single
--- file). Test-under-cursor is `:LvimLang test-func` (test.lua).
---@param args string[]
---@param ctx table
---@return nil
function M.test(args, ctx)
    local root = ctx.root or resolve_root()
    if has_build_zig(root) then
        local argv = { "build", "test" }
        vim.list_extend(argv, args)
        run_zig(root, argv, "zig build test", "Test")
        return
    end
    local file = buffer_file(ctx)
    if not file then
        vim.notify("lvim-lang: no build.zig and no file to test", vim.log.levels.WARN, { title = "lvim-lang" })
        return
    end
    local argv = { "test", file }
    vim.list_extend(argv, args)
    run_zig(vim.fs.dirname(file), argv, "zig test " .. vim.fs.basename(file), "Test")
end

--- `:LvimLang fmt [args]` — `zig fmt` (the formatter built into the `zig` binary). A build.zig
--- project formats the whole tree (`zig fmt .`); a single-file buffer formats just that file.
--- fmt rewrites files on disk; core.runner's `:checktime` on exit reloads open buffers.
---@param args string[]
---@param ctx table
---@return nil
function M.fmt(args, ctx)
    local root = ctx.root or resolve_root()
    local argv = { "fmt" }
    if #args > 0 then
        vim.list_extend(argv, args)
    elseif has_build_zig(root) then
        argv[#argv + 1] = "."
    else
        local file = buffer_file(ctx)
        argv[#argv + 1] = file or "."
    end
    run_zig(root, argv, "zig fmt", "Format")
end

--- The buffer's project root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
