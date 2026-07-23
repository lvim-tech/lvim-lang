-- lvim-lang.providers.haskell.tasks: build / run / test / clean through the project's build tool.
-- Stack and Cabal are the two Haskell build systems; `buildtool.detect` picks the right one at the
-- resolved root and `buildtool.base` the right binary (resolved per project through core.toolchain).
-- build / run / test / clean are fire-and-collect, so they go through core.runner → lvim-tasks (its
-- panel / history / dock). GHC emits `File.hs:line:col: error:` (and multi-line spans), routed to the
-- quickfix by the `haskell` errorformat below. Extra command-line args are appended (e.g.
-- `:LvimLang build --fast`, `:LvimLang test --ta '--match "/Foo/"'`).
--
---@module "lvim-lang.providers.haskell.tasks"

local runner = require("lvim-lang.core.runner")
local buildtool = require("lvim-lang.providers.haskell.buildtool")

local TITLE = { title = "lvim-lang" }

-- GHC diagnostics: a location line `File.hs:line:col: error:` / `…: warning:` (also the
-- `-ferror-spans` forms `File.hs:l:c-c:` and `File.hs:(l,c)-(l,c):`) opens the entry, and the
-- indented lines that follow supply the message. The `%t%*[^:]` trick reads the severity's first
-- char (e → error, w → warning) then the rest up to the colon. Passed to lvim-tasks as a literal
-- errorformat (multi-line diagnostics are best-effort — GHC's message body is free-form).
local HASKELL_EFM = table.concat({
    [[%E%f:%l:%c: error:]],
    [[%W%f:%l:%c: warning:]],
    [[%E%f:%l:%c-%*[0-9]: error:]],
    [[%W%f:%l:%c-%*[0-9]: warning:]],
    [[%E%f:(%l\,%c)-(%*[0-9]\,%*[0-9]): error:]],
    [[%W%f:(%l\,%c)-(%*[0-9]\,%*[0-9]): warning:]],
    [[%C    %m]],
    [[%C  %m]],
    [[%-G%.%#]],
}, ",")

local M = {}

--- Resolve the Haskell project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    return buildtool.root_of(vim.api.nvim_get_current_buf())
end

--- Per-tool argv for each action. `stack`/`cabal` values are the tool subcommands.
---@type table<string, table<"stack"|"cabal", string[]>>
local ACTIONS = {
    build = { stack = { "build" }, cabal = { "build" } },
    run = { stack = { "run" }, cabal = { "run" } },
    test = { stack = { "test" }, cabal = { "test" } },
    clean = { stack = { "clean" }, cabal = { "clean" } },
}

--- Run a build-tool action for a root through lvim-tasks (with the `haskell` errorformat). `env`
--- (optional) is passed to the task process. No-ops with a notice when no build tool is found.
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
            "lvim-lang: no Stack or Cabal project found (need stack.yaml / cabal.project / a *.cabal file)",
            vim.log.levels.WARN,
            TITLE
        )
        return
    end
    local cmd = buildtool.base(tool, root)
    vim.list_extend(cmd, ACTIONS[action][tool])
    vim.list_extend(cmd, args)
    runner.run("haskell", {
        name = tool .. " " .. action,
        cmd = cmd,
        cwd = root,
        group = group,
        matcher = HASKELL_EFM,
        env = env,
    })
end

--- `:LvimLang build [args]` — `stack build` / `cabal build`.
---@param args string[]
---@param ctx table
---@return nil
function M.build(args, ctx)
    run_action(ctx.root or resolve_root(), "build", args, "Build")
end

--- `:LvimLang run [args]` — `stack run` / `cabal run`. When a run config is active
--- (`.lvim/lang/run.lua`) it supplies the executable target, program args and env; extra CLI args
--- append after `--` (both tools forward everything after `--` to the executable).
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    local root = ctx.root or resolve_root()
    local tool = buildtool.detect(root)
    if not tool then
        vim.notify("lvim-lang: no Stack or Cabal project found", vim.log.levels.WARN, TITLE)
        return
    end
    local rc = require("lvim-lang.core.runcfg").active(root)
    local cmd = buildtool.base(tool, root)
    vim.list_extend(cmd, ACTIONS.run[tool])
    local env = nil
    if rc then
        env = rc.env
        -- The executable target the run config names (a `.cabal` `executable` stanza / stack target).
        if rc.target then
            cmd[#cmd + 1] = rc.target
        end
        vim.list_extend(cmd, rc.build_flags or {})
        -- Program arguments after `--` (forwarded to the executable by both stack and cabal).
        local prog = {}
        vim.list_extend(prog, rc.args or {})
        vim.list_extend(prog, args)
        if #prog > 0 then
            cmd[#cmd + 1] = "--"
            vim.list_extend(cmd, prog)
        end
    else
        vim.list_extend(cmd, args)
    end
    runner.run(
        "haskell",
        { name = tool .. " run", cmd = cmd, cwd = root, group = "Run", matcher = HASKELL_EFM, env = env }
    )
end

--- `:LvimLang test [args]` — `stack test` / `cabal test` over the whole suite. (Granular targets —
--- the hspec describe/it under the cursor, the file's suites — are in test.lua.)
---@param args string[]
---@param ctx table
---@return nil
function M.test(args, ctx)
    run_action(ctx.root or resolve_root(), "test", args, "Test")
end

--- `:LvimLang clean [args]` — `stack clean` / `cabal clean`.
---@param args string[]
---@param ctx table
---@return nil
function M.clean(args, ctx)
    run_action(ctx.root or resolve_root(), "clean", args, "Build")
end

--- The Haskell errorformat (exposed so test.lua uses the same matcher).
---@return string
function M.efm()
    return HASKELL_EFM
end

--- The buffer's project root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
