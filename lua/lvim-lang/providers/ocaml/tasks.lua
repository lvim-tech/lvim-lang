-- lvim-lang.providers.ocaml.tasks: one-shot `dune` commands run through lvim-tasks.
-- build / exec / test / utop / fmt are fire-and-collect commands, so they go through core.runner →
-- lvim-tasks with the OCaml problem matcher (a literal errorformat for dune/ocaml diagnostics —
-- `File "f.ml", line L, characters C-C:` followed by an `Error:` / `Warning N:` body — routed to the
-- quickfix list). Extra command-line args are appended (e.g. `:LvimLang build --profile release`,
-- `:LvimLang exec -- --help`).
--
---@module "lvim-lang.providers.ocaml.tasks"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

-- OCaml / dune diagnostics span two lines: a location line then the message. `%E`/`%W` start an
-- error/warning at the location and `%Z`/`%C` collect the following `Error:` / `Warning N:` body, so
-- getqflist folds them into one quickfix entry. matchers.lua treats a non-builtin matcher name as a
-- LITERAL errorformat — the sanctioned seam for a per-language format the built-ins do not cover.
---@type string
local OCAML_EFM = table.concat({
    [[%EFile "%f"\, line %l\, characters %c-%*\d:]],
    [[%WFile "%f"\, line %l\, characters %c-%*\d:]],
    [[%ZError: %m]],
    [[%ZWarning %*\d: %m]],
    [[%C%m]],
}, ",")

local M = {}

--- The OCaml problem-matcher errorformat (exposed so the test / other task modules share it).
---@return string
function M.matcher()
    return OCAML_EFM
end

--- Resolve the dune project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "dune-project", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `dune <argv…>` for a root through lvim-tasks (with the OCaml matcher). `env` (optional) is
--- passed to the task process.
---@param root string
---@param argv string[]
---@param name string
---@param group string
---@param env? table<string, string>
---@return nil
local function run_dune(root, argv, name, group, env)
    local dune = toolchain.resolve("ocaml", "dune", root) or "dune"
    local cmd = { dune }
    vim.list_extend(cmd, argv)
    runner.run("ocaml", { name = name, cmd = cmd, cwd = root, group = group, matcher = OCAML_EFM, env = env })
end

--- `:LvimLang build [args]` — `dune build` (also resolves/installs the project's declared deps into
--- the build tree). Extra args pass straight to dune (e.g. `--profile release`, a target path).
---@param args string[]
---@param ctx table
---@return nil
function M.build(args, ctx)
    local argv = { "build" }
    vim.list_extend(argv, args)
    run_dune(ctx.root or resolve_root(), argv, "dune build", "Build")
end

--- `:LvimLang run [args]` — `dune exec <target>`. The active run config (`.lvim/lang/run.lua`)
--- supplies the executable target, args and env; without one, `dune exec` defaults nothing and dune
--- errors unless a target is given — so we hint the user to add a run config or pass a target.
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    local root = ctx.root or resolve_root()
    local rc = require("lvim-lang.core.runcfg").active(root)
    local argv, env = { "exec" }, nil
    if rc then
        vim.list_extend(argv, rc.dune_flags or {})
        if rc.target then
            argv[#argv + 1] = rc.target
        end
        if #(rc.args or {}) > 0 then
            argv[#argv + 1] = "--"
            vim.list_extend(argv, rc.args)
        end
        vim.list_extend(argv, args)
        env = rc.env
    elseif #args > 0 then
        vim.list_extend(argv, args)
    else
        vim.notify(
            "lvim-lang: `dune exec` needs a target — pass one (`:LvimLang run <target>` / `:LvimLang exec …`) "
                .. "or add a run config (`:LvimLang config`, .lvim/lang/run.lua)",
            vim.log.levels.INFO,
            TITLE
        )
        return
    end
    run_dune(root, argv, "dune exec", "Run", env)
end

--- `:LvimLang exec <target> [-- args]` — `dune exec <target>` (the raw form, no run config).
---@param args string[]
---@param ctx table
---@return nil
function M.exec(args, ctx)
    if #args == 0 then
        vim.notify("lvim-lang: usage — :LvimLang exec <target> [-- args]", vim.log.levels.INFO, TITLE)
        return
    end
    local argv = { "exec" }
    vim.list_extend(argv, args)
    run_dune(ctx.root or resolve_root(), argv, "dune exec " .. args[1], "Run")
end

--- `:LvimLang test [args]` — `dune test` (alias of `dune runtest`; runs the project's test stanzas).
---@param args string[]
---@param ctx table
---@return nil
function M.test(args, ctx)
    local argv = { "test" }
    vim.list_extend(argv, args)
    run_dune(ctx.root or resolve_root(), argv, "dune test", "Test")
end

--- `:LvimLang fmt [args]` — `dune build @fmt --auto-promote` (formats the project with ocamlformat
--- via dune, promoting the formatted result back over the sources). Needs a `.ocamlformat` file.
---@param args string[]
---@param ctx table
---@return nil
function M.fmt(args, ctx)
    local argv = { "build", "@fmt", "--auto-promote" }
    vim.list_extend(argv, args)
    -- fmt rewrites files on disk; core.runner's :checktime on exit reloads open buffers.
    run_dune(ctx.root or resolve_root(), argv, "dune fmt", "Format")
end

--- `:LvimLang utop [args]` — `dune utop <dir>` (a utop REPL with the project's libraries loaded).
--- `dir` defaults to `.` (the whole project); pass a library dir to scope it.
---@param args string[]
---@param ctx table
---@return nil
function M.utop(args, ctx)
    local argv = { "utop" }
    if #args > 0 then
        vim.list_extend(argv, args)
    else
        argv[#argv + 1] = "."
    end
    run_dune(ctx.root or resolve_root(), argv, "dune utop", "Run")
end

--- The buffer's project root (exposed so command wrappers / dap share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
