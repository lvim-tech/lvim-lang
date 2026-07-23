-- lvim-lang.providers.clojure.tasks: run / test through the project's Clojure build tool.
-- The Clojure CLI (deps.edn), Leiningen (project.clj) and Boot (build.boot) are the three build
-- systems; `buildtool.detect` picks the right one at the resolved root and `buildtool.base` the right
-- (toolchain-resolved) binary. run / test are fire-and-collect, so they go through core.runner →
-- lvim-tasks (its panel / history / dock). Clojure / the JVM emit `file:line:col` compiler and test
-- failures, routed to the quickfix by the built-in `generic` matcher. Extra command-line args append.
--
-- The Clojure CLI has no single canonical "run" / "test" verb — projects wire them as ALIASES in
-- deps.edn — so both are configurable (`tasks.clj.run_alias` / `tasks.clj.test_alias`, and
-- `tasks.clj.test_exec` selects `-X` exec vs `-M` main invocation). Leiningen and Boot use their
-- built-in `run` / `test` subcommands.
--
---@module "lvim-lang.providers.clojure.tasks"

local config = require("lvim-lang.config")
local runner = require("lvim-lang.core.runner")
local buildtool = require("lvim-lang.providers.clojure.buildtool")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The clojure provider's `tasks` config block (aliases / exec-vs-main).
---@return table
local function tasks_opts()
    return (config.providers.clojure or {}).tasks or {}
end

--- The Clojure CLI aliases (with defaults).
---@return { run_alias: string, test_alias: string, test_exec: boolean }
local function clj_opts()
    local t = tasks_opts().clj or {}
    return {
        run_alias = t.run_alias or "run",
        test_alias = t.test_alias or "test",
        test_exec = t.test_exec ~= false, -- default true: `-X:test` (Cognitect exec runner)
    }
end

--- Resolve the Clojure project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "deps.edn", "project.clj", "build.boot", "shadow-cljs.edn", ".git" })
            or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The `run` argv tail for a build tool. Clojure CLI runs the `:<run_alias>` alias (`-M:run` by
--- default); Leiningen / Boot use their `run` subcommand.
---@param tool "clj"|"lein"|"boot"
---@return string[]
local function run_tail(tool)
    if tool == "clj" then
        return { "-M:" .. clj_opts().run_alias }
    end
    return { "run" }
end

--- The whole-suite `test` argv tail for a build tool. Clojure CLI runs the `:<test_alias>` alias as an
--- exec fn (`-X:test`, the Cognitect test-runner convention) or a main (`-M:test`) per `test_exec`;
--- Leiningen / Boot use their `test` subcommand.
---@param tool "clj"|"lein"|"boot"
---@return string[]
local function test_tail(tool)
    if tool == "clj" then
        local c = clj_opts()
        return { (c.test_exec and "-X:" or "-M:") .. c.test_alias }
    end
    return { "test" }
end

--- Run a build-tool action for a root through lvim-tasks (with the `generic` problem matcher). `env`
--- (optional) is passed to the task process. No-ops with a notice when no build tool is found.
---@param root string
---@param tail string[]  the tool-specific argv tail (from run_tail / test_tail)
---@param args string[]  extra CLI args appended
---@param label string
---@param group string
---@param env? table<string, string>
---@return nil
local function run_action(root, tail, args, label, group, env)
    local tool = buildtool.detect(root)
    if not tool then
        vim.notify(
            "lvim-lang: no Clojure project found (need deps.edn / project.clj / build.boot)",
            vim.log.levels.WARN,
            TITLE
        )
        return
    end
    local cmd = buildtool.base(tool, root)
    vim.list_extend(cmd, tail)
    vim.list_extend(cmd, args)
    runner.run("clojure", {
        name = vim.fs.basename(cmd[1]) .. " " .. label,
        cmd = cmd,
        cwd = root,
        group = group,
        matcher = "generic",
        env = env,
    })
end

--- `:LvimLang run [args]` — Clojure CLI `-M:run` / `lein run` / `boot run`. When a run config is
--- active (`.lvim/lang/run.lua`) it supplies the main namespace / alias, program args and env: for
--- the Clojure CLI a `main_ns` maps to `-M -m <ns>` and an `alias` to `-M:<alias>` (overriding the
--- default run alias); its `args` are the program arguments. Extra CLI args append.
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    local root = ctx.root or resolve_root()
    local tool = buildtool.detect(root)
    if not tool then
        vim.notify("lvim-lang: no Clojure project found", vim.log.levels.WARN, TITLE)
        return
    end
    local rc = require("lvim-lang.core.runcfg").active(root)
    local tail, env = run_tail(tool), nil
    if rc then
        env = rc.env
        if tool == "clj" then
            if rc.alias then
                tail = { "-M:" .. rc.alias }
            elseif rc.main_ns then
                tail = { "-M", "-m", rc.main_ns }
            end
        end
        local prog = {}
        vim.list_extend(prog, rc.args or {})
        vim.list_extend(prog, args)
        run_action(root, tail, prog, "run", "Run", env)
        return
    end
    run_action(root, tail, args, "run", "Run", env)
end

--- `:LvimLang test [args]` — the whole test suite: Clojure CLI `-X:test` / `-M:test` (per
--- `tasks.clj.test_exec`), `lein test`, `boot test`.
---@param args string[]
---@param ctx table
---@return nil
function M.test(args, ctx)
    local root = ctx.root or resolve_root()
    run_action(root, test_tail(buildtool.detect(root) or "clj"), args, "test", "Test")
end

--- The buffer's project root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

-- lvim-tasks templates (via the provider's `tasks` field): the arg-less run / test actions, each
-- detecting the build tool and applying only when a Clojure project is present at the resolved root.
---@type table[]
M.templates = {}
for _, action in ipairs({ "run", "test" }) do
    M.templates[#M.templates + 1] = {
        name = "clojure " .. action,
        desc = "Clojure: " .. action .. " (auto-detected build tool)",
        group = action == "run" and "Run" or "Test",
        builder = function(ctx)
            local root = (ctx and ctx.root) or resolve_root()
            local tool = buildtool.detect(root)
            if not tool then
                return nil
            end
            local cmd = buildtool.base(tool, root)
            vim.list_extend(cmd, action == "run" and run_tail(tool) or test_tail(tool))
            return {
                name = vim.fs.basename(cmd[1]) .. " " .. action,
                cmd = cmd,
                cwd = root,
                group = action == "run" and "Run" or "Test",
                matcher = "generic",
            }
        end,
    }
end

return M
