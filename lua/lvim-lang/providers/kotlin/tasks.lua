-- lvim-lang.providers.kotlin.tasks: build / run / test through the project's build tool.
-- Gradle is the near-universal Kotlin build system (Maven via the kotlin-maven-plugin is the
-- fallback); `buildtool.detect` picks the right one at the resolved root and `buildtool.base` the
-- right binary (the `./gradlew` / `./mvnw` wrapper when the project ships one, else the toolchain /
-- system `gradle` / `mvn`). build / run / test are fire-and-collect, so they go through core.runner
-- → lvim-tasks (its panel / history / dock). kotlinc / gradle emit `file:line:col: error: message`,
-- routed to the quickfix by the built-in `generic` matcher. Extra command-line args are appended
-- (e.g. `:LvimLang build --info`, `:LvimLang test --tests Foo`).
--
---@module "lvim-lang.providers.kotlin.tasks"

local runner = require("lvim-lang.core.runner")
local buildtool = require("lvim-lang.providers.kotlin.buildtool")

local TITLE = { title = "lvim-lang" }

-- Kotlin's project-root markers (Gradle scripts / wrapper, then Maven, then `.git`).
---@type string[]
local ROOT_PATTERNS = {
    "build.gradle.kts",
    "build.gradle",
    "settings.gradle.kts",
    "settings.gradle",
    "pom.xml",
    ".git",
}

local M = {}

--- Resolve the Kotlin project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, ROOT_PATTERNS) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Per-tool argv for each action. `gradle` values are Gradle task names; `maven` values are Maven
--- goals. `run` maps to Gradle's Application plugin `run` task and Maven's `exec:java` goal.
---@type table<string, table<"gradle"|"maven", string[]>>
local ACTIONS = {
    build = { gradle = { "build" }, maven = { "compile" } },
    run = { gradle = { "run" }, maven = { "exec:java" } },
    test = { gradle = { "test" }, maven = { "test" } },
}

--- Run a build-tool action for a root through lvim-tasks (with the `generic` problem matcher).
--- `env` (optional) is passed to the task process. No-ops with a notice when no build tool is found.
---@param root string
---@param action string
---@param args string[]
---@param group string
---@param env? table<string, string>
---@return nil
local function run_action(root, action, args, group, env)
    local tool = buildtool.detect(root)
    if not tool then
        vim.notify(
            "lvim-lang: no Gradle or Maven project found (need build.gradle* / settings.gradle* / pom.xml)",
            vim.log.levels.WARN,
            TITLE
        )
        return
    end
    local cmd = buildtool.base(tool, root)
    vim.list_extend(cmd, ACTIONS[action][tool])
    vim.list_extend(cmd, args)
    runner.run("kotlin", {
        name = vim.fs.basename(cmd[1]) .. " " .. action,
        cmd = cmd,
        cwd = root,
        group = group,
        matcher = "generic",
        env = env,
    })
end

--- `:LvimLang build [args]` — `gradle build` / `mvn compile`.
---@param args string[]
---@param ctx table
---@return nil
function M.build(args, ctx)
    run_action(ctx.root or resolve_root(), "build", args, "Build")
end

--- `:LvimLang run [args]` — `gradle run` / `mvn exec:java`. When a run config is active
--- (`.lvim/lang/run.lua`) it supplies the main class (Gradle `--args` / Maven
--- `-Dexec.mainClass`), program args and env; extra CLI args append.
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    local root = ctx.root or resolve_root()
    local rc = require("lvim-lang.core.runcfg").active(root)
    local tool = buildtool.detect(root)
    if not tool then
        vim.notify("lvim-lang: no Gradle or Maven project found", vim.log.levels.WARN, TITLE)
        return
    end
    local extra, env = {}, nil
    if rc then
        env = rc.env
        -- The program arguments the run config passes to the application.
        local prog = {}
        vim.list_extend(prog, rc.args or {})
        vim.list_extend(prog, args)
        if tool == "gradle" then
            if rc.main_class then
                extra[#extra + 1] = "-PmainClass=" .. rc.main_class
            end
            if #prog > 0 then
                extra[#extra + 1] = "--args=" .. table.concat(prog, " ")
            end
        else
            if rc.main_class then
                extra[#extra + 1] = "-Dexec.mainClass=" .. rc.main_class
            end
            if #prog > 0 then
                extra[#extra + 1] = "-Dexec.args=" .. table.concat(prog, " ")
            end
        end
    else
        extra = args
    end
    run_action(root, "run", extra, "Run", env)
end

--- `:LvimLang test [args]` — `gradle test` / `mvn test` over the whole suite.
---@param args string[]
---@param ctx table
---@return nil
function M.test(args, ctx)
    run_action(ctx.root or resolve_root(), "test", args, "Test")
end

--- The buffer's project root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
