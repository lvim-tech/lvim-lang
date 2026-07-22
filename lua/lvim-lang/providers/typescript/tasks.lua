-- lvim-lang.providers.typescript.tasks: running JS/TS through lvim-tasks.
-- Everything is PACKAGE-MANAGER aware (providers.typescript.pm detects npm / pnpm / yarn / bun):
-- `script` runs a package.json script (`<pm> run <name>`), `install` / `build` / `dev` are the common
-- ones spelled out, and `run` runs the current file (node for JS, a project-local tsx for TS) or the
-- active run config. Fire-and-collect, so they go through core.runner → lvim-tasks with the built-in
-- `typescript` matcher routing `file(line,col): error TSxxxx` to the quickfix list.
--
---@module "lvim-lang.providers.typescript.tasks"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")
local pm = require("lvim-lang.providers.typescript.pm")

local TITLE = { title = "lvim-lang" }

local M = {}

--- Resolve the JS/TS project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "package.json", "tsconfig.json", "jsconfig.json", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run a command for a root through lvim-tasks (with the `typescript` matcher). `env` optional.
---@param root string
---@param cmd string[]
---@param name string
---@param group string
---@param env? table<string, string>
---@return nil
local function run(root, cmd, name, group, env)
    runner.run("typescript", { name = name, cmd = cmd, cwd = root, group = group, matcher = "typescript", env = env })
end

--- The current buffer's file path (absolute), or nil.
---@return string|nil
local function current_file()
    local name = vim.api.nvim_buf_get_name(0)
    return name ~= "" and name or nil
end

--- The command that RUNS a JS/TS file: `node` for `.js/.mjs/.cjs`, a project-local `tsx` for
--- `.ts/.tsx` (else nil + a hint). Resolved against `root`.
---@param file string
---@param root string
---@return string[]|nil
local function file_runner(file, root)
    local node = toolchain.resolve("typescript", "node", root) or "node"
    if file:match("%.[mc]?jsx?$") then
        return { node, file }
    end
    -- TypeScript needs a loader; prefer a project-local tsx, then ts-node.
    for _, bin in ipairs({ "tsx", "ts-node" }) do
        local p = vim.fs.joinpath(vim.fs.root(root, { "package.json" }) or root, "node_modules", ".bin", bin)
        if vim.fn.executable(p) == 1 then
            return { p, file }
        end
    end
    vim.notify(
        "lvim-lang: install `tsx` (or ts-node) to run TypeScript directly, or use :LvimLang script",
        vim.log.levels.WARN,
        TITLE
    )
    return nil
end

--- `:LvimLang run [args]` — run the current file (or the active run config) under node / tsx. A run
--- config supplies a `script` (`<pm> run <script>`) or a `file` (run that file), plus args / env.
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    local root = ctx.root or resolve_root()
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.script then
        local cmd = { pm.detect(root), "run", rc.script }
        vim.list_extend(cmd, rc.args or {})
        vim.list_extend(cmd, args)
        run(root, cmd, "run " .. rc.script, "Run", rc.env)
        return
    end
    local file = (rc and rc.file) or args[1] or current_file()
    if not file then
        vim.notify("lvim-lang: no file to run (open a buffer or add a run config)", vim.log.levels.WARN, TITLE)
        return
    end
    local cmd = file_runner(file, root)
    if not cmd then
        return
    end
    vim.list_extend(cmd, rc and rc.args or {})
    vim.list_extend(cmd, (rc or args[1]) and args or { unpack(args, 2) })
    run(root, cmd, "run " .. vim.fs.basename(file), "Run", rc and rc.env)
end

--- `:LvimLang script [name] [args]` — run a package.json script (`<pm> run <name>`). With no name,
--- pick one through the canonical picker.
---@param args string[]
---@param ctx table
---@return nil
function M.script(args, ctx)
    local root = ctx.root or resolve_root()
    local function go(name)
        if not name then
            return
        end
        local cmd = { pm.detect(root), "run", name }
        vim.list_extend(cmd, { unpack(args, 2) })
        run(root, cmd, pm.detect(root) .. " run " .. name, "Run")
    end
    if args[1] then
        go(args[1])
    else
        pm.pick_script(root, go)
    end
end

--- `:LvimLang install [args]` — install dependencies (`<pm> install`).
---@param args string[]
---@param ctx table
---@return nil
function M.install(args, ctx)
    local root = ctx.root or resolve_root()
    local cmd = { pm.detect(root), "install" }
    vim.list_extend(cmd, args)
    run(root, cmd, pm.detect(root) .. " install", "Dependencies")
end

--- `:LvimLang build [args]` — run the `build` script (`<pm> run build`).
---@param args string[]
---@param ctx table
---@return nil
function M.build(args, ctx)
    local root = ctx.root or resolve_root()
    local cmd = { pm.detect(root), "run", "build" }
    vim.list_extend(cmd, args)
    run(root, cmd, "build", "Build")
end

--- `:LvimLang dev [args]` — run the `dev` script (`<pm> run dev`).
---@param args string[]
---@param ctx table
---@return nil
function M.dev(args, ctx)
    local root = ctx.root or resolve_root()
    local cmd = { pm.detect(root), "run", "dev" }
    vim.list_extend(cmd, args)
    run(root, cmd, "dev", "Run")
end

--- The buffer's project root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

-- lvim-tasks templates: `install` (always, when a package.json is present) and each common
-- package.json script (build / dev / test / start / lint) that the project actually defines.
---@type table[]
M.templates = {
    {
        name = "install dependencies",
        desc = "install JS/TS dependencies (auto-detected package manager)",
        group = "Dependencies",
        builder = function(ctx)
            local root = (ctx and ctx.root) or resolve_root()
            if vim.fn.filereadable(vim.fs.joinpath(root, "package.json")) ~= 1 then
                return nil
            end
            return {
                name = pm.detect(root) .. " install",
                cmd = { pm.detect(root), "install" },
                cwd = root,
                group = "Dependencies",
                matcher = "typescript",
            }
        end,
    },
}
for _, script in ipairs({ "build", "dev", "test", "start", "lint" }) do
    M.templates[#M.templates + 1] = {
        name = "npm run " .. script,
        desc = "run the package.json `" .. script .. "` script",
        group = script == "test" and "Test" or (script == "build" and "Build" or "Run"),
        builder = function(ctx)
            local root = (ctx and ctx.root) or resolve_root()
            local has = false
            for _, s in ipairs(pm.scripts(root)) do
                has = has or s.name == script
            end
            if not has then
                return nil
            end
            local manager = pm.detect(root)
            return {
                name = manager .. " run " .. script,
                cmd = { manager, "run", script },
                cwd = root,
                group = script == "test" and "Test" or (script == "build" and "Build" or "Run"),
                matcher = "typescript",
            }
        end,
    }
end

return M
