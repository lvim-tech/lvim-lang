-- lvim-lang.providers.csharp.tasks: one-shot `dotnet` CLI commands run through lvim-tasks.
-- build / run / test / clean are fire-and-collect commands (no persistent daemon), so they go through
-- core.runner → lvim-tasks and land in its panel / history / dock. The C# compiler emits
-- `file(line,col): error CSxxxx: message` diagnostics, which match the built-in `typescript` problem
-- matcher shape (`%f(%l,%c): … %m`), so that matcher routes MSBuild errors to the quickfix list.
-- Extra command-line args are appended (e.g. `:LvimLang build -c Release`, `:LvimLang run -- --flag`).
--
---@module "lvim-lang.providers.csharp.tasks"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local M = {}

--- Whether a directory entry name is a C# project-root marker (a solution / project file, or `.git`).
--- `.sln`/`.csproj` are GLOBS, so a function matcher is used with vim.fs.root (which supports one).
---@param name string
---@return boolean
local function is_root_marker(name)
    return name:match("%.sln$") ~= nil or name:match("%.csproj$") ~= nil or name == ".git"
end

--- Resolve the .NET project/solution root for the current buffer (nearest `.sln`/`.csproj`, else the
--- `.git` root, else the file's directory, else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, is_root_marker) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `dotnet <argv…>` for a root through lvim-tasks (with the `typescript` C# problem matcher).
--- `env` (optional) is passed to the task process.
---@param root string
---@param argv string[]
---@param name string
---@param group string
---@param env? table<string, string>
---@return nil
local function run_dotnet(root, argv, name, group, env)
    local dotnet = toolchain.resolve("csharp", "dotnet", root) or "dotnet"
    local cmd = { dotnet }
    vim.list_extend(cmd, argv)
    runner.run("csharp", { name = name, cmd = cmd, cwd = root, group = group, matcher = "typescript", env = env })
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

--- The buffer's project root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
