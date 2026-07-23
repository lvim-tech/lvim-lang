-- lvim-lang.providers.unison.tasks: the NON-INTERACTIVE `ucm` invocations, run through lvim-tasks.
-- `ucm` is primarily an INTERACTIVE codebase manager (a REPL you drive by typing commands); most of
-- what you do with Unison — add/update definitions, run the type-checker, run `test`, browse the
-- codebase — happens inside that live session and cannot be scripted from the shell. Only a small
-- set of `ucm` sub-invocations are genuinely non-interactive, and those are the ONLY ones exposed
-- here (fire-and-collect, no persistent daemon), so we never fabricate a build/test flow Unison does
-- not actually have:
--   * `ucm run <main>`            — execute a `'{IO, Exception} ()` main already in the codebase.
--   * `ucm run.file <file> <main>` — type-check a scratch file and execute its named main.
--   * `ucm transcript <file.md>`  — execute a transcript (the canonical scripted/CI escape hatch;
--                                    a transcript can itself contain a `test` block, which is how
--                                    Unison runs tests non-interactively — see docs/providers/unison.md).
-- Runs land in the lvim-tasks panel / history / dock. Unison diagnostics come from the LSP (the
-- running UCM), so no problem matcher is wired here.
--
---@module "lvim-lang.providers.unison.tasks"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

local M = {}

--- Resolve the Unison project root for the current buffer (the git repo, else the file's dir / cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The resolved `ucm` binary for a root (or the bare name as a last resort).
---@param root string
---@return string
local function ucm_bin(root)
    return toolchain.resolve("unison", "ucm", root) or "ucm"
end

--- Run `ucm <argv…>` for a root through lvim-tasks (Unison diagnostics come from the LSP, so no matcher).
---@param root string
---@param argv string[]
---@param name string
---@param group string
---@return nil
local function run_ucm(root, argv, name, group)
    local cmd = { ucm_bin(root) }
    vim.list_extend(cmd, argv)
    runner.run("unison", { name = name, cmd = cmd, cwd = root, group = group })
end

--- `:LvimLang run <main>` — `ucm run <main>`: execute a `'{IO, Exception} ()` main from the codebase,
--- without entering the interactive UCM prompt. The main's fully-qualified name is required.
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    if #args == 0 then
        vim.notify("lvim-lang: usage — :LvimLang run <main-function-name>", vim.log.levels.INFO, TITLE)
        return
    end
    run_ucm(ctx.root, { "run", unpack(args) }, "ucm run " .. args[1], "Run")
end

--- `:LvimLang run-file [main]` — `ucm run.file <current .u file> [main]`: type-check the current
--- scratch file and execute its named main (defaults to `main`). Requires a `.u` buffer on disk.
---@param args string[]
---@param ctx table
---@return nil
function M.run_file(args, ctx)
    local file = vim.api.nvim_buf_get_name(ctx.bufnr or 0)
    if file == "" or not (file:match("%.u$") or file:match("%.uu$")) then
        vim.notify("lvim-lang: run-file needs a saved Unison scratch (.u) buffer", vim.log.levels.WARN, TITLE)
        return
    end
    local main = args[1] or "main"
    run_ucm(ctx.root, { "run.file", file, main }, "ucm run.file " .. main, "Run")
end

--- `:LvimLang transcript [file.md]` — `ucm transcript <file.md>`: execute a transcript non-interactively
--- (the scripted/CI escape hatch; a transcript may contain a `test` block to run tests). Defaults to the
--- current buffer when it is a `.md` file.
---@param args string[]
---@param ctx table
---@return nil
function M.transcript(args, ctx)
    local file = args[1]
    if not file then
        local buf = vim.api.nvim_buf_get_name(ctx.bufnr or 0)
        if buf ~= "" and buf:match("%.md$") then
            file = buf
        end
    end
    if not file then
        vim.notify("lvim-lang: usage — :LvimLang transcript <file.md>", vim.log.levels.INFO, TITLE)
        return
    end
    run_ucm(ctx.root, { "transcript", file }, "ucm transcript " .. vim.fs.basename(file), "Build")
end

--- The buffer's project root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
