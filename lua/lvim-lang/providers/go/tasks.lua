-- lvim-lang.providers.go.tasks: one-shot `go` CLI commands run through lvim-tasks.
-- build / run / test / vet / generate are fire-and-collect commands (no persistent daemon), so they
-- go through core.runner → lvim-tasks and land in its panel / history / dock, with the built-in `go`
-- problem matcher routing `file:line:col: message` errors to the quickfix list. Extra command-line
-- args are appended (e.g. `:LvimLang build -race`, `:LvimLang run ./cmd/foo`).
--
---@module "lvim-lang.providers.go.tasks"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local M = {}

--- Resolve the Go module/workspace root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "go.work", "go.mod", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `go <argv…>` for a root through lvim-tasks (with the `go` problem matcher). `env` (optional)
--- is passed to the task process.
---@param root string
---@param argv string[]
---@param name string
---@param group string
---@param env? table<string, string>
---@return nil
local function run_go(root, argv, name, group, env)
    local go = toolchain.resolve("go", "go", root) or "go"
    local cmd = { go }
    vim.list_extend(cmd, argv)
    runner.run("go", { name = name, cmd = cmd, cwd = root, group = group, matcher = "go", env = env })
end

--- `:LvimLang build [args]` — `go build ./...`.
---@param args string[]
---@param ctx table
---@return nil
function M.build(args, ctx)
    local argv = { "build" }
    vim.list_extend(argv, #args > 0 and args or { "./..." })
    run_go(ctx.root, argv, "go build", "Build")
end

--- `:LvimLang run [target] [args]` — `go run …`. When a run config is active (`.lvim/lang/run.lua`)
--- it supplies the package, build flags, build tags, program args and env; an explicit `[target]`
--- overrides the package and extra args append. With no run config: `go run .` (or the given target).
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    local rc = require("lvim-lang.core.runcfg").active(ctx.root)
    local argv, env = { "run" }, nil
    if rc then
        vim.list_extend(argv, rc.build_flags or {})
        if rc.tags then
            argv[#argv + 1] = "-tags"
            argv[#argv + 1] = type(rc.tags) == "table" and table.concat(rc.tags, ",") or rc.tags
        end
        argv[#argv + 1] = args[1] or rc.package or "." -- explicit target overrides the config package
        vim.list_extend(argv, rc.args or {}) -- program args from the config
        for i = 2, #args do -- extra CLI args append
            argv[#argv + 1] = args[i]
        end
        env = rc.env
    else
        vim.list_extend(argv, #args > 0 and args or { "." })
    end
    run_go(ctx.root, argv, "go run", "Run", env)
end

--- `:LvimLang test [args]` — `go test ./...`. (Test-under-cursor / coverage come in G5.)
---@param args string[]
---@param ctx table
---@return nil
function M.test(args, ctx)
    local argv = { "test" }
    vim.list_extend(argv, #args > 0 and args or { "./..." })
    run_go(ctx.root, argv, "go test", "Test")
end

--- `:LvimLang vet [args]` — `go vet ./...`.
---@param args string[]
---@param ctx table
---@return nil
function M.vet(args, ctx)
    local argv = { "vet" }
    vim.list_extend(argv, #args > 0 and args or { "./..." })
    run_go(ctx.root, argv, "go vet", "Lint")
end

--- `:LvimLang generate [args]` — `go generate ./...`.
---@param args string[]
---@param ctx table
---@return nil
function M.generate(args, ctx)
    local argv = { "generate" }
    vim.list_extend(argv, #args > 0 and args or { "./..." })
    run_go(ctx.root, argv, "go generate", "Build")
end

--- The buffer's project root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
