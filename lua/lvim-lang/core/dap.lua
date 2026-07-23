-- lvim-lang.core.dap: a thin bridge to lvim-dap (lvim-lang owns no debugger engine).
-- The bulk of registration is automatic: a provider's server-config carries a `dap` field
-- ({ adapters, configurations }) and lvim-ls registers it with lvim-dap on attach. This module
-- only adds the extra seam that is NOT static: a DYNAMIC configuration provider, for launch
-- configs that depend on live state (the selected device, the active run config's flavor/target).
--
---@module "lvim-lang.core.dap"

local M = {}

-- ── Declarative DAP (the factory seam) ────────────────────────────────────────────────────────────
-- A declarative provider declares a COMPACT `dap` in its DATA; build() resolves the adapter binaries
-- per root and expands it into the `{ adapters, configurations }` shape the server-config `dap` field
-- expects — so a data provider debugs with no bespoke module, wherever a real DAP adapter exists.
--   adapters = { <name> = { kind = "executable"|"server", tool?, args? } | function(cb,cfg) … end }
--   configurations = { <ft> = { { adapter = "<name>", request, name, program = "pick"|"${file}"|…, … } } }
--   bin_dir? = "…"   -- default dir the program picker starts in (relative to the root)

--- Resolve a DAP adapter binary for `root`: the provider's toolchain, else PATH, else the bare name.
---@param provider string
---@param tool string
---@param root string
---@return string
local function bin(provider, tool, root)
    local r = require("lvim-lang.core.toolchain").resolve(provider, tool, root)
    if r and r ~= "" then
        return r
    end
    local p = vim.fn.exepath(tool)
    return p ~= "" and p or tool
end

--- A file/program picker, defaulting under `dir`.
---@param dir string|nil
---@return fun(): string
function M.pick_program(dir)
    return function()
        return vim.fn.input("Path to executable: ", dir and (dir .. "/") or "", "file")
    end
end

--- The pid to attach to: nvim-dap's process picker when available, else a typed pid.
---@return fun(): integer
function M.pick_pid()
    return function()
        local ok, u = pcall(require, "dap.utils")
        if ok and type(u.pick_process) == "function" then
            return u.pick_process()
        end
        return tonumber(vim.fn.input("Process id: ")) or 0
    end
end

--- Expand a compact DATA.dap into the lvim-ls server-config `dap` spec, resolved for `root`.
---@param provider string
---@param dap table
---@param root string
---@return table
function M.build(provider, dap, root)
    local adapters = {}
    for name, a in pairs(dap.adapters or {}) do
        if type(a) == "function" then
            adapters[name] = a -- an inline adapter (e.g. the nlua attach adapter) — used verbatim
        else
            local cmd = bin(provider, a.tool or name, root)
            if a.kind == "server" then
                adapters[name] = function(cb, _c)
                    cb({
                        type = "server",
                        port = "${port}",
                        executable = { command = cmd, args = a.args or { "--port", "${port}" } },
                    })
                end
            else
                adapters[name] = { type = "executable", command = cmd, args = a.args or {} }
            end
        end
    end

    local default_dir = dap.bin_dir and vim.fs.joinpath(root, dap.bin_dir) or root
    local configurations = {}
    for ft, cfgs in pairs(dap.configurations or {}) do
        configurations[ft] = {}
        for _, c in ipairs(cfgs) do
            local cfg = vim.deepcopy(c)
            cfg.type = c.adapter or c.type -- `adapter` names the entry in `adapters`; becomes DAP `type`
            cfg.adapter = nil
            if cfg.program == "pick" then
                cfg.program = M.pick_program(default_dir)
            end
            if cfg.pid == "pick" then
                cfg.pid = M.pick_pid()
            end
            configurations[ft][#configurations[ft] + 1] = cfg
        end
    end
    return { adapters = adapters, configurations = configurations }
end

--- Register a dynamic dap configuration provider (lvim-dap's register_provider seam). `fn(bufnr)`
--- returns extra configurations gathered alongside the statically-registered ones. Idempotent by
--- id; degrades to a no-op when lvim-dap is unavailable.
---@param id string
---@param fn fun(bufnr: integer): table[]
---@return nil
function M.register_configs(id, fn)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok or type(dap.register_provider) ~= "function" then
        return
    end
    dap.register_provider(id, fn)
end

return M
