-- lvim-lang.providers.python.dap: Python debugging through lvim-dap, backed by debugpy.
-- The static adapter + base launch configurations are handed to lvim-ls via the basedpyright server
-- config's `dap` field (auto-registered with lvim-dap on attach). debugpy is a python MODULE, so the
-- adapter runs `<python> -m debugpy.adapter` — under an interpreter that HAS debugpy: the mason
-- debugpy install's bundled interpreter if present, else the project venv. The debuggee itself runs
-- under the PROJECT interpreter (`python` resolved fresh per launch), so a program is debugged in the
-- same environment it runs in. `:LvimLang debug` continues / starts a session; `:LvimLang debug-test`
-- debugs exactly the pytest test under the cursor.
--
---@module "lvim-lang.providers.python.dap"

local toolchain = require("lvim-lang.core.toolchain")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The Python project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", "Pipfile", ".git" })
            or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The project interpreter for a root (else `python3`) — the debuggee runs under this.
---@param root string
---@return string
local function project_python(root)
    return toolchain.resolve("python", "python", root) or "python3"
end

--- The interpreter that RUNS debugpy's adapter (must have debugpy importable): an explicit
--- config path → the mason debugpy install's bundled venv python → the project interpreter.
---@param root string
---@return string
local function adapter_python(root)
    local o = require("lvim-lang.config").providers.python or {}
    if o.debugpy_python and vim.fn.executable(o.debugpy_python) == 1 then
        return o.debugpy_python
    end
    local ok, pkg = pcall(require, "lvim-pkg")
    if ok and type(pkg.package_path) == "function" then
        for _, rel in ipairs({ "venv/bin/python", "venv/Scripts/python.exe" }) do
            local p = vim.fs.joinpath(pkg.package_path("debugpy"), rel)
            if vim.fn.executable(p) == 1 then
                return p
            end
        end
    end
    return project_python(root)
end

--- The debugpy executable adapter: `<adapter python> -m debugpy.adapter`, resolved per session cwd.
---@return fun(callback: fun(adapter: table), config: table)
local function adapter()
    return function(callback, config)
        local root = (config and config.cwd) or vim.uv.cwd() or "."
        callback({
            type = "executable",
            command = adapter_python(root),
            args = { "-m", "debugpy.adapter" },
        })
    end
end

--- The project interpreter for the CURRENT buffer's root — the `python` field of a launch config, so
--- the debuggee runs under the project venv (evaluated by lvim-dap at launch).
---@return string
local function debuggee_python()
    return project_python(root_of(vim.api.nvim_get_current_buf()))
end

--- The static `dap` field for the basedpyright server config (adapter + base configurations).
---@return table
function M.spec()
    return {
        adapters = { python = adapter() },
        configurations = {
            python = {
                {
                    type = "python",
                    request = "launch",
                    name = "Launch file",
                    program = "${file}",
                    cwd = "${workspaceFolder}",
                    console = "integratedTerminal",
                    python = debuggee_python,
                },
                {
                    type = "python",
                    request = "launch",
                    name = "Launch module",
                    module = function()
                        return vim.fn.input("Module name: ")
                    end,
                    cwd = "${workspaceFolder}",
                    console = "integratedTerminal",
                    python = debuggee_python,
                },
                {
                    type = "python",
                    request = "launch",
                    name = "Launch file with args",
                    program = "${file}",
                    args = function()
                        return vim.split(vim.fn.input("Arguments: "), " +", { trimempty = true })
                    end,
                    cwd = "${workspaceFolder}",
                    console = "integratedTerminal",
                    python = debuggee_python,
                },
                {
                    type = "python",
                    request = "attach",
                    name = "Attach (localhost:5678)",
                    connect = { host = "127.0.0.1", port = 5678 },
                },
            },
        },
    }
end

--- The enclosing `def test_*` under the cursor and any enclosing `class Test*` (treesitter), or nil.
---@param bufnr integer
---@return string|nil func, string|nil class
local function enclosing_test(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil, nil
    end
    local func, class
    while node do
        local t = node:type()
        if t == "function_definition" and not func then
            local n = node:field("name")[1]
            local name = n and vim.treesitter.get_node_text(n, bufnr)
            if name and name:match("^test") then
                func = name
            end
        elseif t == "class_definition" and not class then
            local n = node:field("name")[1]
            class = n and vim.treesitter.get_node_text(n, bufnr) or nil
        end
        node = node:parent()
    end
    return func, class
end

--- `:LvimLang debug` — continue / start a debug session (lvim-dap picks a configuration).
---@param _args string[]
---@param _ctx table
---@return nil
function M.debug(_args, _ctx)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok then
        vim.notify("lvim-lang: lvim-dap not available", vim.log.levels.WARN, TITLE)
        return
    end
    dap.continue()
end

--- `:LvimLang debug-test` — debug exactly the pytest test under the cursor (`debugpy` runs
--- `python -m pytest <node id>` under the project interpreter).
---@param _args string[]
---@param ctx table
---@return nil
function M.debug_test(_args, ctx)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok then
        vim.notify("lvim-lang: lvim-dap not available", vim.log.levels.WARN, TITLE)
        return
    end
    local func, class = enclosing_test(ctx.bufnr)
    if not func then
        vim.notify("lvim-lang: cursor is not inside a `def test_*` function", vim.log.levels.WARN, TITLE)
        return
    end
    local file = vim.api.nvim_buf_get_name(ctx.bufnr)
    if file == "" then
        return
    end
    local root = ctx.root or root_of(ctx.bufnr)
    local node = class and (file .. "::" .. class .. "::" .. func) or (file .. "::" .. func)
    dap.run({
        type = "python",
        request = "launch",
        name = "Debug test " .. func,
        module = "pytest",
        args = { node, "-v" },
        cwd = root,
        console = "integratedTerminal",
        python = project_python(root),
    })
end

return M
