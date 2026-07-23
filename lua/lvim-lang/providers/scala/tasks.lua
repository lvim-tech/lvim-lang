-- lvim-lang.providers.scala.tasks: build / run / test through the project's build tool.
-- sbt / mill / bloop are the three Scala build systems; `buildtool.detect` picks the right one at the
-- resolved root and `buildtool.base` the right binary (the `./sbt` / `./mill` wrapper when the project
-- ships one, else the toolchain / system binary). build / run / test are fire-and-collect, so they go
-- through core.runner → lvim-tasks (its panel / history / dock). scalac / sbt / mill emit
-- `file:line: error: message`, routed to the quickfix by the built-in `generic` matcher. Extra
-- command-line args are appended (e.g. `:LvimLang test -- -oD`).
--
-- The three tools are asymmetric: sbt runs a bare `run` / `runMain <main>`; mill addresses a MODULE
-- (`<module>.run`), so a single-target run needs providers.scala.mill_module; bloop addresses a
-- PROJECT (`run <project>`). Whole-suite build / test map cleanly on all three.
--
---@module "lvim-lang.providers.scala.tasks"

local runner = require("lvim-lang.core.runner")
local buildtool = require("lvim-lang.providers.scala.buildtool")

local TITLE = { title = "lvim-lang" }

-- Scala's project-root markers (build scripts, then `.git`).
---@type string[]
local ROOT_PATTERNS = { "build.sbt", "build.sc", ".git" }

local M = {}

--- Resolve the Scala project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, ROOT_PATTERNS) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The tail argv for a whole-suite action (build / test) on a tool. bloop takes its project name.
---@param tool "sbt"|"mill"|"bloop"
---@param action "build"|"test"
---@param root string
---@return string[]
local function suite_args(tool, action, root)
    if tool == "sbt" then
        return { action == "build" and "compile" or "test" }
    elseif tool == "mill" then
        return { action == "build" and "__.compile" or "__.test" }
    end
    -- bloop
    return { action == "build" and "compile" or "test", buildtool.project(root) }
end

--- The tail argv for `run` on a tool, applying an optional main class + program args. Returns nil
--- (after a notice) when mill has no runnable target (no `mill_module` and no run config main class).
---@param tool "sbt"|"mill"|"bloop"
---@param root string
---@param main_class string|nil
---@param prog string[]        program arguments
---@return string[]|nil
local function run_args(tool, root, main_class, prog)
    if tool == "sbt" then
        -- sbt takes each argv as a full command; `runMain <main> [args]` is ONE command string.
        if main_class then
            local s = "runMain " .. main_class
            if #prog > 0 then
                s = s .. " " .. table.concat(prog, " ")
            end
            return { s }
        end
        return { "run" }
    elseif tool == "mill" then
        local mod = buildtool.module(root)
        if not mod then
            vim.notify(
                'lvim-lang: mill needs a module to run — set providers.scala.mill_module (e.g. "app")',
                vim.log.levels.WARN,
                TITLE
            )
            return nil
        end
        if main_class then
            local args = { mod .. ".runMain", main_class }
            vim.list_extend(args, prog)
            return args
        end
        local args = { mod .. ".run" }
        vim.list_extend(args, prog)
        return args
    end
    -- bloop: run <project> [-m <main>] [-- <args>]
    local args = { "run", buildtool.project(root) }
    if main_class then
        vim.list_extend(args, { "-m", main_class })
    end
    if #prog > 0 then
        args[#args + 1] = "--"
        vim.list_extend(args, prog)
    end
    return args
end

--- Run a build-tool action for a root through lvim-tasks (with the `generic` problem matcher).
--- `env` (optional) is passed to the task process. No-ops with a notice when no build tool is found.
---@param root string
---@param action "build"|"test"
---@param args string[]
---@param group string
---@return nil
local function run_suite(root, action, args, group)
    local tool = buildtool.detect(root)
    if not tool then
        vim.notify(
            "lvim-lang: no sbt / mill / bloop project found (need build.sbt / build.sc / a .bloop dir)",
            vim.log.levels.WARN,
            TITLE
        )
        return
    end
    local cmd = buildtool.base(tool, root)
    vim.list_extend(cmd, suite_args(tool, action, root))
    vim.list_extend(cmd, args)
    runner.run("scala", {
        name = vim.fs.basename(cmd[1]) .. " " .. action,
        cmd = cmd,
        cwd = root,
        group = group,
        matcher = "generic",
    })
end

--- `:LvimLang build [args]` — `sbt compile` / `mill __.compile` / `bloop compile <project>`.
---@param args string[]
---@param ctx table
---@return nil
function M.build(args, ctx)
    run_suite(ctx.root or resolve_root(), "build", args, "Build")
end

--- `:LvimLang run [args]` — `sbt run` / `mill <module>.run` / `bloop run <project>`. When a run
--- config is active (`.lvim/lang/run.lua`) it supplies the main class + program args + env; extra CLI
--- args append.
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    local root = ctx.root or resolve_root()
    local tool = buildtool.detect(root)
    if not tool then
        vim.notify("lvim-lang: no sbt / mill / bloop project found", vim.log.levels.WARN, TITLE)
        return
    end
    local rc = require("lvim-lang.core.runcfg").active(root)
    local main_class, env = nil, nil
    local prog = {}
    if rc then
        main_class = rc.main_class
        env = rc.env
        vim.list_extend(prog, rc.args or {})
    end
    vim.list_extend(prog, args)
    local tail = run_args(tool, root, main_class, prog)
    if not tail then
        return
    end
    local cmd = buildtool.base(tool, root)
    vim.list_extend(cmd, tail)
    runner.run("scala", {
        name = vim.fs.basename(cmd[1]) .. " run",
        cmd = cmd,
        cwd = root,
        group = "Run",
        matcher = "generic",
        env = env,
    })
end

--- `:LvimLang test [args]` — `sbt test` / `mill __.test` / `bloop test <project>` over the whole
--- suite. Extra args append (sbt passes test-framework args after `--`, e.g. `:LvimLang test -- -oD`).
---@param args string[]
---@param ctx table
---@return nil
function M.test(args, ctx)
    run_suite(ctx.root or resolve_root(), "test", args, "Test")
end

--- The buffer's project root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
