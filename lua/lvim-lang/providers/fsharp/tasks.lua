-- lvim-lang.providers.fsharp.tasks: one-shot `dotnet` CLI commands run through lvim-tasks.
-- build / run / test / clean are fire-and-collect commands (no persistent daemon), so they go through
-- core.runner → lvim-tasks and land in its panel / history / dock. The F# compiler emits
-- `file(line,col): error FSxxxx: message` diagnostics, which match the built-in `typescript` problem
-- matcher shape (`%f(%l,%c): … %m`), so that matcher routes MSBuild errors to the quickfix list.
-- Extra command-line args are appended (e.g. `:LvimLang build -c Release`, `:LvimLang run -- --flag`).
--
-- `format` is separate: it runs Fantomas (the F# formatter) on the current file, or on the paths
-- given as args. Fantomas formats files IN PLACE (it has no stdin mode), so it is a task — core.runner
-- runs `:checktime` on exit, reloading the formatted buffer. The binary is resolved through
-- core.toolchain, and installed on demand (core.ensure) when it is not yet available.
--
---@module "lvim-lang.providers.fsharp.tasks"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")
local ensure = require("lvim-lang.core.ensure")

local TITLE = { title = "lvim-lang" }

local M = {}

--- Whether a directory entry name is an F# project-root marker (a solution / project file, the paket
--- manifest, or `.git`). `.sln`/`.fsproj` are GLOBS, so a function matcher is used with vim.fs.root
--- (which supports one).
---@param name string
---@return boolean
local function is_root_marker(name)
    return name:match("%.sln$") ~= nil
        or name:match("%.fsproj$") ~= nil
        or name == "paket.dependencies"
        or name == ".git"
end

--- Resolve the .NET project/solution root for the current buffer (nearest `.sln`/`.fsproj`/
--- `paket.dependencies`, else the `.git` root, else the file's directory, else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, is_root_marker) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `dotnet <argv…>` for a root through lvim-tasks (with the `typescript` .NET problem matcher).
--- `env` (optional) is passed to the task process.
---@param root string
---@param argv string[]
---@param name string
---@param group string
---@param env? table<string, string>
---@return nil
local function run_dotnet(root, argv, name, group, env)
    local dotnet = toolchain.resolve("fsharp", "dotnet", root) or "dotnet"
    local cmd = { dotnet }
    vim.list_extend(cmd, argv)
    runner.run("fsharp", { name = name, cmd = cmd, cwd = root, group = group, matcher = "typescript", env = env })
end

--- `:LvimLang build [args]` — `dotnet build`.
---@param args string[]
---@param ctx table
---@return nil
function M.build(args, ctx)
    local argv = { "build" }
    vim.list_extend(argv, args)
    run_dotnet(ctx.root, argv, "dotnet build", "Build")
end

--- `:LvimLang run [args]` — `dotnet run`. When a run config is active (`.lvim/lang/run.lua`) it
--- supplies the target project, build configuration, program args and env; extra CLI args append.
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    local rc = require("lvim-lang.core.runcfg").active(ctx.root)
    local argv, env = { "run" }, nil
    if rc then
        if rc.project then
            argv[#argv + 1] = "--project"
            argv[#argv + 1] = rc.project
        end
        if rc.configuration then
            argv[#argv + 1] = "-c"
            argv[#argv + 1] = rc.configuration
        end
        vim.list_extend(argv, rc.dotnet_flags or {})
        if #(rc.args or {}) > 0 then
            argv[#argv + 1] = "--"
            vim.list_extend(argv, rc.args)
        end
        vim.list_extend(argv, args) -- extra CLI args append
        env = rc.env
    else
        vim.list_extend(argv, args)
    end
    run_dotnet(ctx.root, argv, "dotnet run", "Run", env)
end

--- `:LvimLang test [args]` — `dotnet test`. (Test-under-cursor / test-file are in test.lua.)
---@param args string[]
---@param ctx table
---@return nil
function M.test(args, ctx)
    local argv = { "test" }
    vim.list_extend(argv, args)
    run_dotnet(ctx.root, argv, "dotnet test", "Test")
end

--- `:LvimLang clean [args]` — `dotnet clean`.
---@param args string[]
---@param ctx table
---@return nil
function M.clean(args, ctx)
    local argv = { "clean" }
    vim.list_extend(argv, args)
    run_dotnet(ctx.root, argv, "dotnet clean", "Build")
end

--- `:LvimLang format [paths…]` — run Fantomas on the paths (default: the current buffer's file).
--- Fantomas formats in place; core.runner's `:checktime` on exit reloads the buffer. The binary is
--- resolved through core.toolchain, and installed on demand when it is not yet present.
---@param args string[]
---@param ctx table
---@return nil
function M.format(args, ctx)
    local root = ctx.root or resolve_root()
    -- Default target: the current file; else the whole root.
    local targets = args
    if #targets == 0 then
        local name = vim.api.nvim_buf_get_name(ctx.bufnr or vim.api.nvim_get_current_buf())
        targets = { name ~= "" and name or "." }
    end
    --- Run `<fantomas> <targets…>` at the root through lvim-tasks (Lint group).
    ---@param fantomas string
    local function run(fantomas)
        local cmd = { fantomas }
        vim.list_extend(cmd, targets)
        runner.run("fsharp", { name = "fantomas", cmd = cmd, cwd = root, group = "Lint" })
    end
    local resolved = toolchain.resolve("fsharp", "fantomas", root)
    if resolved then
        return run(resolved)
    end
    -- Not resolved through the toolchain — install (or find on PATH) on demand, then run.
    ensure.tool("fantomas", "fantomas", run)
end

--- The buffer's project root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
