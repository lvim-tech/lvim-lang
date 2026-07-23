-- lvim-lang.providers.zig.dap: Zig debugging through lvim-dap, backed by lldb-dap.
-- Zig produces native binaries with DWARF debug info (`zig build` → `zig-out/bin/`, or a single
-- `zig build-exe`), so it debugs with LLVM's own `lldb-dap` adapter (an `executable`-type adapter,
-- the modern LLDB DAP server). The static adapter + base launch/attach configurations are handed to
-- lvim-ls via the zls server config's `dap` field (auto-registered with lvim-dap on attach). A
-- codelldb entry is also offered as an alternative (the catalog default is lldb-dap). `:LvimLang
-- debug` continues / starts a session; the launch config prompts for the executable, defaulting
-- under the project's `zig-out/bin/` output dir.
--
---@module "lvim-lang.providers.zig.dap"

local M = {}

--- The zig config block.
---@return table
local function opts()
    return require("lvim-lang.config").providers.zig or {}
end

--- The Zig project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "build.zig", "build.zig.zon", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Resolve the lldb-dap binary: an explicit config path → PATH (the mason install).
---@return string
local function lldb_dap_bin()
    local o = opts()
    if o.lldb_dap_path and vim.fn.executable(o.lldb_dap_path) == 1 then
        return o.lldb_dap_path
    end
    local p = vim.fn.exepath("lldb-dap")
    return p ~= "" and p or "lldb-dap"
end

--- Resolve the codelldb binary: an explicit config path → PATH (the mason install).
---@return string
local function codelldb_bin()
    local o = opts()
    if o.codelldb_path and vim.fn.executable(o.codelldb_path) == 1 then
        return o.codelldb_path
    end
    local p = vim.fn.exepath("codelldb")
    return p ~= "" and p or "codelldb"
end

--- The codelldb server adapter: `codelldb --port ${port}` (lvim-dap resolves a free port).
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

--- Prompt for the executable to debug, defaulting under the project's Zig output dir
--- (config.bin_dir, default "zig-out/bin").
---@return string
local function pick_program()
    local root = root_of(vim.api.nvim_get_current_buf())
    local base = root .. "/" .. (opts().bin_dir or "zig-out/bin") .. "/"
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

--- The static `dap` field for the zls server config (adapters + base configurations for Zig). The
--- launch config prompts for the executable (defaulting under `zig-out/bin/`); an attach config
--- attaches to a running pid.
---@return table
function M.spec()
    return {
        adapters = {
            ["lldb-dap"] = { type = "executable", command = lldb_dap_bin(), args = {} },
            codelldb = codelldb_adapter(),
        },
        configurations = {
            zig = {
                {
                    type = "lldb-dap",
                    request = "launch",
                    name = "Launch (lldb-dap)",
                    program = pick_program,
                    cwd = "${workspaceFolder}",
                    stopOnEntry = false,
                },
                {
                    type = "lldb-dap",
                    request = "attach",
                    name = "Attach (lldb-dap)",
                    pid = pick_pid,
                },
                {
                    type = "codelldb",
                    request = "launch",
                    name = "Launch (codelldb)",
                    program = pick_program,
                    cwd = "${workspaceFolder}",
                    stopOnEntry = false,
                },
            },
        },
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
