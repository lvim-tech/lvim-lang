-- lvim-lang.providers.python.toolchain: the Python toolchain spec.
-- The `python` interpreter is VENV-AWARE (see providers.python.venv): an explicit config path → the
-- user's persisted interpreter choice → an auto-detected environment (.venv / venv / poetry / pipenv
-- / conda / $VIRTUAL_ENV) → a version manager (mise / asdf / pyenv, honouring the project's pin) →
-- `python3` / `python` on PATH. The tools (basedpyright-langserver / ruff) resolve from the SAME
-- environment first (a project that `pip install`ed them wins), then the mason bin, then PATH — so a
-- project-local tool is preferred over the shared one. Detection only; nothing is installed here.
--
---@module "lvim-lang.providers.python.toolchain"

local config = require("lvim-lang.config")
local venv = require("lvim-lang.providers.python.venv")

--- The python config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.python or {}
end

--- Run the user's `python_lookup_cmd` and take its first non-empty line as the interpreter path.
---@return string|nil
local function lookup_python()
    local cmd = opts().python_lookup_cmd
    if type(cmd) ~= "string" or cmd == "" then
        return nil
    end
    local out = vim.fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 or type(out) ~= "table" then
        return nil
    end
    for _, line in ipairs(out) do
        local trimmed = vim.trim(line)
        if trimmed ~= "" then
            return trimmed
        end
    end
    return nil
end

--- Resolve `python` through the configured version manager, honouring the project's pin for `root`.
--- `version_manager` may be a name ("mise"|"asdf"|"pyenv"), false to disable, or a function(root).
--- Default: try mise then asdf then pyenv (`<mgr> which python`).
---@param root string
---@return string|nil
local function via_version_manager(root)
    local vm = opts().version_manager
    if vm == false then
        return nil
    end
    if type(vm) == "function" then
        return vm(root)
    end
    local managers = type(vm) == "string" and { vm } or { "mise", "asdf", "pyenv" }
    for _, mgr in ipairs(managers) do
        if vim.fn.executable(mgr) == 1 then
            local out = vim.system({ mgr, "which", "python" }, { cwd = root, text = true }):wait()
            if out.code == 0 then
                local path = vim.trim(out.stdout or "")
                if path ~= "" and vim.fn.executable(path) == 1 then
                    return path
                end
            end
        end
    end
    return nil
end

--- Build a resolver that returns the explicit config path under `key`, or nil.
---@param key string
---@return fun(): string|nil
local function explicit(key)
    return function()
        return opts()[key]
    end
end

--- Resolve a tool `bin` inside the project's environment: `<env>/bin/<bin>`, if executable. The
--- environment is the resolved interpreter's directory (so a project that `pip install`ed the tool
--- into its venv is preferred over the shared mason copy).
---@param bin string
---@return fun(root: string): string|nil
local function in_venv(bin)
    return function(root)
        local py = require("lvim-lang.core.toolchain").resolve("python", "python", root)
        local dir = py and venv.dir(py)
        if not dir then
            return nil
        end
        for _, sub in ipairs({ "bin", "Scripts" }) do
            local p = vim.fs.joinpath(dir, sub, bin)
            if vim.fn.executable(p) == 1 then
                return p
            end
        end
        return nil
    end
end

--- Resolve a tool `bin` inside the mason bin directory (lvim-pkg), if installed there.
---@param bin string
---@return fun(): string|nil
local function in_mason(bin)
    return function()
        local ok, pkg = pcall(require, "lvim-pkg")
        if not ok or type(pkg.bin_dir) ~= "function" then
            return nil
        end
        local path = vim.fs.joinpath(pkg.bin_dir(), bin)
        return vim.fn.executable(path) == 1 and path or nil
    end
end

---@type LvimLangToolchainSpec
return {
    tools = {
        -- The interpreter: config → persisted pick → auto-detected env → version manager → PATH.
        python = {
            { kind = "path", value = explicit("python_path") },
            { kind = "path", value = venv.selected },
            {
                kind = "path",
                value = function(root)
                    return (select(1, venv.detect(root)))
                end,
            },
            { kind = "path", value = via_version_manager },
            { kind = "which", value = "python3" },
            { kind = "which", value = "python" },
        },
        -- basedpyright's language-server binary: config → project env → mason → PATH.
        basedpyright = {
            { kind = "path", value = explicit("basedpyright_path") },
            { kind = "path", value = in_venv("basedpyright-langserver") },
            { kind = "path", value = in_mason("basedpyright-langserver") },
            { kind = "which", value = "basedpyright-langserver" },
        },
        -- basedpyright's CLI (used for `--createstub`): config → project env → mason → PATH.
        ["basedpyright-cli"] = {
            { kind = "path", value = in_venv("basedpyright") },
            { kind = "path", value = in_mason("basedpyright") },
            { kind = "which", value = "basedpyright" },
        },
        ruff = {
            { kind = "path", value = explicit("ruff_path") },
            { kind = "path", value = in_venv("ruff") },
            { kind = "path", value = in_mason("ruff") },
            { kind = "which", value = "ruff" },
        },
    },

    --- `<bin> --version` — first NON-EMPTY line, trimmed (python / basedpyright / ruff use `--version`).
    ---@param bin string
    ---@return string|nil
    version = function(bin)
        local out = vim.fn.systemlist({ bin, "--version" })
        if vim.v.shell_error ~= 0 or type(out) ~= "table" then
            return nil
        end
        for _, line in ipairs(out) do
            local trimmed = vim.trim(line)
            if trimmed ~= "" then
                return trimmed
            end
        end
        return nil
    end,
}
