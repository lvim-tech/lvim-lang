-- lvim-lang.providers.python.venv: Python interpreter / virtual-environment resolution.
-- Python's idiosyncratic concern (the analog of Flutter's daemon or Rust's rustup): the `python`
-- that a project runs under lives in a virtual environment, and EVERYTHING — the LSP's import
-- resolution, the debugger, the test runner, `pip`/`poetry` — must use THAT interpreter, not the
-- global one. This module discovers the project's environment and lets the user pick one; the
-- choice is persisted per root through the shared store (like the run config), and the toolchain's
-- `python` strategies read `selected()` / `detect()` here.
--
-- Detection is cheap-first and side-effect free: the active `$VIRTUAL_ENV` / `$CONDA_PREFIX`, then
-- an in-tree `.venv` / `venv` directory, then poetry / pipenv (only when their marker file AND CLI
-- exist, since those shell out). `dir()` derives the env directory from the interpreter path so the
-- LSP can point `python.pythonPath` at it. Detection only — nothing is created here (`create` runs
-- `python -m venv` as a task).
--
---@module "lvim-lang.providers.python.venv"

local ui = require("lvim-lang.core.ui")

local M = {}

--- The `bin/python` (or Windows `Scripts/python.exe`) inside an environment directory, if executable.
---@param envdir string
---@return string|nil
local function python_in(envdir)
    for _, rel in ipairs({ "bin/python", "bin/python3", "Scripts/python.exe" }) do
        local p = vim.fs.joinpath(envdir, rel)
        if vim.fn.executable(p) == 1 then
            return p
        end
    end
    return nil
end

--- The environment DIRECTORY for an interpreter path (`<env>/bin/python` → `<env>`), for the LSP's
--- `venvPath` / a human label. Returns nil for a bare system `python` not inside a `bin` dir.
---@param python string
---@return string|nil
function M.dir(python)
    local bin = vim.fs.dirname(python) -- <env>/bin
    if not bin then
        return nil
    end
    local base = vim.fs.basename(bin)
    if base == "bin" or base == "Scripts" then
        return vim.fs.dirname(bin)
    end
    return nil
end

--- Run `cmd` in `root` and return its first non-empty trimmed stdout line (nil on failure). Used for
--- the poetry / pipenv env-path queries — guarded so a missing / erroring CLI is simply "no env".
---@param cmd string[]
---@param root string
---@return string|nil
local function first_line(cmd, root)
    if vim.fn.executable(cmd[1]) ~= 1 then
        return nil
    end
    local out = vim.system(cmd, { cwd = root, text = true }):wait()
    if out.code ~= 0 then
        return nil
    end
    for _, line in ipairs(vim.split(out.stdout or "", "\n")) do
        local t = vim.trim(line)
        if t ~= "" then
            return t
        end
    end
    return nil
end

--- AUTO-DETECT the project's interpreter (ignoring any persisted user choice), cheap checks first.
--- Order: active `$VIRTUAL_ENV` → in-tree `.venv` / `venv` → poetry (pyproject + CLI) → pipenv
--- (Pipfile + CLI) → active `$CONDA_PREFIX`. Returns the interpreter path and a short KIND label.
---@param root string
---@return string|nil python, string|nil kind
function M.detect(root)
    local venv = vim.env.VIRTUAL_ENV
    if venv and venv ~= "" then
        local p = python_in(venv)
        if p then
            return p, "$VIRTUAL_ENV"
        end
    end
    for _, name in ipairs({ ".venv", "venv" }) do
        local p = python_in(vim.fs.joinpath(root, name))
        if p then
            return p, name
        end
    end
    if vim.fn.filereadable(vim.fs.joinpath(root, "pyproject.toml")) == 1 then
        local envdir = first_line({ "poetry", "env", "info", "--path" }, root)
        if envdir then
            local p = python_in(envdir)
            if p then
                return p, "poetry"
            end
        end
    end
    if vim.fn.filereadable(vim.fs.joinpath(root, "Pipfile")) == 1 then
        local envdir = first_line({ "pipenv", "--venv" }, root)
        if envdir then
            local p = python_in(envdir)
            if p then
                return p, "pipenv"
            end
        end
    end
    local conda = vim.env.CONDA_PREFIX
    if conda and conda ~= "" then
        local p = python_in(conda)
        if p then
            return p, "conda"
        end
    end
    return nil, nil
end

--- The PERSISTED interpreter choice for a root (still-executable), or nil. The user's explicit pick
--- through `M.pick`, remembered across sessions via the shared store.
---@param root string
---@return string|nil
function M.selected(root)
    local db = require("lvim-lang.core.store").get()
    local path = db and db.python_interpreters and db.python_interpreters[root]
    if path and vim.fn.executable(path) == 1 then
        return path
    end
    return nil
end

--- Persist (or clear, with nil) the interpreter choice for a root, drop the cached toolchain
--- resolutions so the next `resolve` re-runs, and nudge the statusline.
---@param root string
---@param path string|nil
---@return nil
function M.set_selected(root, path)
    local db = require("lvim-lang.core.store").get()
    if db then
        local all = db.python_interpreters or {}
        all[root] = path
        db.python_interpreters = all
    end
    require("lvim-lang.core.toolchain").invalidate("python", root)
    pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "LvimLangStatus" })
end

--- Discover candidate interpreters for the picker: the auto-detected env, in-tree `.venv` / `venv`,
--- and the `python3` / `python` on PATH. De-duplicated by resolved path.
---@param root string
---@return { path: string, label: string, kind: string }[]
function M.list(root)
    local items, seen = {}, {}
    local function add(path, kind)
        if not path or path == "" or seen[path] then
            return
        end
        seen[path] = true
        items[#items + 1] = { path = path, label = path, kind = kind }
    end
    local detected, kind = M.detect(root)
    add(detected, kind or "detected")
    for _, name in ipairs({ ".venv", "venv" }) do
        add(python_in(vim.fs.joinpath(root, name)), name)
    end
    for _, bin in ipairs({ "python3", "python" }) do
        local p = vim.fn.exepath(bin)
        add(p ~= "" and p or nil, "PATH")
    end
    return items
end

--- Pick an interpreter through the canonical picker; the choice is persisted for the root.
---@param root string
---@param cb? fun(path: string|nil)
---@return nil
function M.pick(root, cb)
    local candidates = M.list(root)
    if #candidates == 0 then
        vim.notify(
            "lvim-lang: no Python interpreter found — create one with :LvimLang venv create",
            vim.log.levels.INFO,
            { title = "lvim-lang" }
        )
        if cb then
            cb(nil)
        end
        return
    end
    local ic = (require("lvim-lang.config").providers.python or {}).icons or {}
    local active = M.selected(root) or select(1, M.detect(root))
    local items, current = {}, nil
    for i, c in ipairs(candidates) do
        items[i] = { label = ("%s  (%s)"):format(c.path, c.kind), icon = ic.venv or "󰌠", path = c.path }
        if active and active == c.path then
            current = i
        end
    end
    ui.pick({ title = "Python interpreter", items = items, current = current }, function(item)
        if not item then
            if cb then
                cb(nil)
            end
            return
        end
        M.set_selected(root, item.path)
        vim.notify("lvim-lang: interpreter → " .. item.path, vim.log.levels.INFO, { title = "lvim-lang" })
        if cb then
            cb(item.path)
        end
    end)
end

--- Create a virtual environment (`<base python> -m venv <name>`, default `.venv`) at the root,
--- through lvim-tasks, then select it once it exists. Uses a base interpreter that is NOT itself a
--- venv (a version manager / PATH python) so `venv` is available.
---@param root string
---@param name? string  environment directory name (default ".venv")
---@return nil
function M.create(root, name)
    name = name or ".venv"
    local base = vim.fn.exepath("python3")
    if base == "" then
        base = vim.fn.exepath("python")
    end
    if base == "" then
        vim.notify("lvim-lang: no base `python` on PATH to create a venv", vim.log.levels.WARN, { title = "lvim-lang" })
        return
    end
    require("lvim-lang.core.runner").run("python", {
        name = "python -m venv " .. name,
        cmd = { base, "-m", "venv", name },
        cwd = root,
        group = "Dependencies",
        matcher = "python",
        hooks = {
            on_exit = function()
                vim.schedule(function()
                    local p = python_in(vim.fs.joinpath(root, name))
                    if p then
                        M.set_selected(root, p)
                        vim.notify("lvim-lang: created + selected " .. p, vim.log.levels.INFO, { title = "lvim-lang" })
                    end
                end)
            end,
        },
    })
end

--- Command adapter (`:LvimLang venv [create [name]]`): with no argument, PICK an interpreter; with
--- `create [name]`, create a virtual environment and select it.
---@param args string[]
---@param ctx table  { provider, root, bufnr }
---@return nil
function M.command(args, ctx)
    if args[1] == "create" then
        M.create(ctx.root, args[2])
    else
        M.pick(ctx.root)
    end
end

return M
