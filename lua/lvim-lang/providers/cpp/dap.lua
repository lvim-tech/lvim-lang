-- lvim-lang.providers.cpp.dap: C / C++ debugging through lvim-dap.
-- Two adapters are offered (the catalog default is codelldb): CodeLLDB (`codelldb --port ${port}`, a
-- `server` adapter — the LLVM debugger, best for clang/gcc binaries) and cpptools (`OpenDebugAD7`,
-- the `cppdbg` executable adapter — the classic MI/GDB bridge). Both are handed to lvim-ls via the
-- clangd server config's `dap` field (auto-registered with lvim-dap on attach). Launch configs prompt
-- for the executable (defaulting under the build dir); an attach config attaches to a running pid.
--
---@module "lvim-lang.providers.cpp.dap"

local M = {}

--- The cpp config block.
---@return table
local function opts()
    return require("lvim-lang.config").providers.cpp or {}
end

--- The C/C++ project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "compile_commands.json", "CMakeLists.txt", "Makefile", ".clangd", ".git" })
            or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Resolve the CodeLLDB binary: an explicit config path → PATH (the mason install).
---@return string
local function codelldb_bin()
    local o = opts()
    if o.codelldb_path and vim.fn.executable(o.codelldb_path) == 1 then
        return o.codelldb_path
    end
    local p = vim.fn.exepath("codelldb")
    return p ~= "" and p or "codelldb"
end

--- Resolve the cpptools debug adapter binary (`OpenDebugAD7`): an explicit config path → PATH.
---@return string
local function cpptools_bin()
    local o = opts()
    if o.cpptools_path and vim.fn.executable(o.cpptools_path) == 1 then
        return o.cpptools_path
    end
    local p = vim.fn.exepath("OpenDebugAD7")
    return p ~= "" and p or "OpenDebugAD7"
end

--- The CodeLLDB server adapter: `codelldb --port ${port}` (lvim-dap resolves a free port).
---@return fun(callback: fun(adapter: table), config: table)
local function codelldb_adapter()
    return function(callback, _config)
        callback({
            type = "server",
            port = "${port}",
            executable = { command = codelldb_bin(), args = { "--port", "${port}" } },
        })
    end
end

--- Prompt for the executable to debug, defaulting under the build dir of the current buffer's root.
---@return string
local function pick_program()
    local root = root_of(vim.api.nvim_get_current_buf())
    local base = root .. "/" .. (opts().build_dir or "build") .. "/"
    return vim.fn.input("Path to executable: ", base, "file")
end

--- The pid to attach to: the nvim-dap process picker when available, else a typed pid.
---@return integer
local function pick_pid()
    local ok, dap_utils = pcall(require, "dap.utils")
    if ok and type(dap_utils.pick_process) == "function" then
        return dap_utils.pick_process()
    end
    return tonumber(vim.fn.input("Process id: ")) or 0
end

--- The static `dap` field for the clangd server config (adapters + base configurations for every
--- C/C++ filetype). The same config list is shared across filetypes (the debugger does not care).
---@return table
function M.spec()
    local codelldb_cfgs = {
        {
            type = "codelldb",
            request = "launch",
            name = "Launch (CodeLLDB)",
            program = pick_program,
            cwd = "${workspaceFolder}",
            stopOnEntry = false,
        },
        {
            type = "codelldb",
            request = "attach",
            name = "Attach (CodeLLDB)",
            pid = pick_pid,
        },
    }
    local cpptools_cfgs = {
        {
            type = "cppdbg",
            request = "launch",
            name = "Launch (cpptools/GDB)",
            program = pick_program,
            cwd = "${workspaceFolder}",
            stopAtEntry = false,
            MIMode = "gdb",
        },
    }
    local configurations = {}
    for _, ft in ipairs({ "c", "cpp", "objc", "objcpp" }) do
        local list = {}
        vim.list_extend(list, codelldb_cfgs)
        vim.list_extend(list, cpptools_cfgs)
        configurations[ft] = list
    end
    return {
        adapters = {
            codelldb = codelldb_adapter(),
            cppdbg = { type = "executable", command = cpptools_bin(), args = {}, id = "cppdbg" },
        },
        configurations = configurations,
    }
end

--- `:LvimLang debug` — continue / start a debug session (lvim-dap picks a configuration).
---@param _args string[]
---@param _ctx table
---@return nil
function M.debug(_args, _ctx)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok then
        vim.notify("lvim-lang: lvim-dap not available", vim.log.levels.WARN, { title = "lvim-lang" })
        return
    end
    dap.continue()
end

return M
