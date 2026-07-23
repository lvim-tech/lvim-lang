-- lvim-lang.core.declarative: the data→provider factory, the ONE base builder for every provider.
-- A provider's common 80% (name/filetypes/root, toolchain resolution, the LSP server catalog + its
-- generic server-config module, requirements, health, statusline, straight-line commands) is IDENTICAL
-- across languages — the bespoke providers currently hand-write and duplicate it. This module produces
-- that base from a compact LvimLangSpecData record, in the SAME shape a bespoke provider builds, so the
-- registry / catalog / LSP fan-out / commands treat it identically.
--
-- BASE + EXTEND (the model, user-locked 2026-07-23):
--   * Tier 2/3/4 (pure data): providers.registry loads the data file → build() → register(). Zero Lua.
--   * Tier 1 (bespoke): `local spec, defaults = declarative.build(data)` for the base, then EXTEND the
--     returned (mutable) spec with the idiosyncratic parts — override a generated command with a
--     project-shape-adaptive impl, add spec.dap / spec.decorations / a daemon, a richer toolchain.version
--     — and register(spec, defaults). One code path for the shared skeleton; bespoke code only for the 20%.
--
-- Two products:
--   * build(data)        → spec, defaults   (a mutable LvimLangProvider + its config seed)
--   * server_module(key) → the lvim-ls server-config table for one server key, generated from the owning
--     provider's live catalog. Installed into package.preload as lvim-lang.servers.<key> (via
--     install_server_shims) so lvim-ls' `require("lvim-lang.servers.<key>")` resolves with no hand-written
--     file — UNLESS a real servers/<key>.lua exists (a bespoke override), which always wins.
--
---@module "lvim-lang.core.declarative"

local config = require("lvim-lang.config")
local detect = require("lvim-lang.core.detect")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local runner = require("lvim-lang.core.runner")
local requirements = require("lvim-lang.core.requirements")
local runcfg = require("lvim-lang.core.runcfg")

---@class LvimLangRuntimeData      -- a system runtime/compiler/SDK tool a provider needs (user-owned, not mason)
---@field bin       string          -- executable name (e.g. "node", "kotlinc")
---@field key?      string          -- toolchain key (defaults to bin)
---@field lookup_key? string        -- config key holding a lookup command (printed path) — the swiftly/shim seam
---@field sdkman?   string          -- SDKMAN candidate name (java / kotlin / gradle / scala) — enables that backend
---@field managers? string[]        -- version-manager candidate list (e.g. { "rustup", "mise", "asdf" }); default mise/asdf/sdkman
---@field require?  boolean         -- surface as a requirement at activation/health (default true for the single `runtime`)
---@field label?    string          -- health / requirement label (a requirement is only surfaced when set + require)
---@field hint?     string          -- how to install it when missing
---@field severity? "error"|"warn"|"info"  -- requirement level (default "warn")

---@class LvimLangCommandData       -- one straight-line :LvimLang subcommand
---@field cmd       string[]         -- argv template; cmd[1] is resolved through the toolchain when possible
---@field tool?     string           -- toolchain key for cmd[1] (defaults to cmd[1])
---@field ensure?   { mason: string, bin?: string }  -- install this mason tool on first run (on-demand)
---@field group?    string           -- lvim-tasks display group (Build/Run/Test/…), default "Run"
---@field matcher?  string           -- lvim-tasks problem matcher name
---@field desc?     string

---@class LvimLangSpecData
---@field name          string
---@field filetypes     string[]
---@field root_patterns string[]
---@field runtime?      LvimLangRuntimeData                -- sugar for a single required runtime
---@field runtimes?     LvimLangRuntimeData[]              -- several runtime/SDK tools (kotlin: kotlinc/java/gradle …)
---@field version?      fun(bin: string): string|nil       -- toolchain version prober override (default detect.version)
---@field lsp?          table                              -- { servers = {…}, default = string|string[] } (as core.catalog reads)
---@field ft?           table<string, table>               -- per-filetype catalog (LvimLangFtBlock)
---@field project_dirs? string[]                           -- project-local bin dirs probed before mason (vendor/bin, node_modules/.bin, bin)
---@field tools?        (string|table)[]                   -- extra mason install-union helpers (a mason name, or { mason, bin? })
---@field commands?     table<string, LvimLangCommandData>
---@field dap?          table                              -- compact DAP (see core.dap.build): { adapters, configurations, bin_dir? }
---@field icons?        table

local M = {}

--- server key → owning provider name. Read by server_module() to reach the live catalog; populated by
--- build() for every provider assembled through the factory (bespoke via base+extend included).
---@type table<string, string>
M.owners = {}

-- Every provider's server-config modules resolve under this require prefix (matches core.lsp DIR_PREFIX).
local DIR_PREFIX = "lvim-lang.servers"

--- Resolve the current buffer's project root for a set of markers (server config is evaluated per root).
---@param patterns string[]
---@return string
local function current_root(patterns)
    local buf = vim.api.nvim_get_current_buf()
    local nm = vim.api.nvim_buf_get_name(buf)
    if nm ~= "" then
        return vim.fs.root(buf, patterns) or vim.fs.dirname(nm)
    end
    return vim.uv.cwd() or "."
end

--- The LSP client_capabilities fragment: lvim-cmp's when present, else the Neovim defaults.
---@return table
local function capabilities()
    local ok, cmp = pcall(require, "lvim-cmp")
    if ok and type(cmp.capabilities) == "function" then
        return cmp.capabilities()
    end
    return vim.lsp.protocol.make_client_capabilities()
end

--- The provider's runtime/SDK tools as a normalised list: the `runtimes` list, else the single
--- `runtime` sugar (which defaults require=true). Empty when the language has no user-owned runtime.
---@param data LvimLangSpecData
---@return LvimLangRuntimeData[]
local function runtimes_of(data)
    if data.runtimes then
        return data.runtimes
    end
    if data.runtime then
        return { vim.tbl_extend("keep", data.runtime, { require = true }) }
    end
    return {}
end

--- Synthesise the toolchain spec: a resolvable strategy set per tool. Mason tools (each LSP server, and
--- each ft formatter/linter/debugger, and each extra `tools` helper) resolve explicit → mason → PATH; each
--- runtime/SDK tool resolves explicit → lookup → version-manager (mise/asdf/SDKMAN) → PATH. The server-config
--- module later resolves its binary via toolchain.resolve(name, <server key>, root), so every server key
--- MUST appear here. `version` is the data override, else the generic `<bin> --version` prober.
---@param name string
---@param data LvimLangSpecData
---@return LvimLangToolchainSpec
local function build_toolchain(name, data)
    ---@type table<string, LvimLangToolchainStrategy[]>
    local tools = {}
    for _, rt in ipairs(runtimes_of(data)) do
        local key = rt.key or rt.bin
        tools[key] = detect.runtime_strategies(
            name,
            key,
            rt.bin,
            { lookup_key = rt.lookup_key, sdkman = rt.sdkman, managers = rt.managers }
        )
    end
    local pdirs = data.project_dirs
    for key, se in pairs((data.lsp and data.lsp.servers) or {}) do
        if se.mason then
            tools[key] = detect.mason_strategies(name, key, se.bin or se.mason, pdirs)
        end
    end
    for _, ftblock in pairs(data.ft or {}) do
        for _, kind in ipairs({ "formatters", "linters", "debuggers" }) do
            for key, te in pairs(ftblock[kind] or {}) do
                if te.mason and not tools[key] then
                    tools[key] = detect.mason_strategies(name, key, te.bin or te.mason, pdirs)
                end
            end
        end
    end
    for _, t in ipairs(data.tools or {}) do
        local mason, bin
        if type(t) == "table" then
            mason, bin = t.mason or t[1], t.bin
        else
            mason = t
        end
        if type(mason) == "string" then
            local tkey = (type(bin) == "string" and bin) or mason
            if not tools[tkey] then
                tools[tkey] = detect.mason_strategies(name, tkey, tkey, pdirs)
            end
        end
    end
    return { tools = tools, version = data.version or detect.version }
end

--- Turn the command data into :LvimLang subcommand impls. Each resolves cmd[1] through the toolchain
--- (mason bin dir → PATH) per root, appends the user's extra args, and runs through core.runner →
--- lvim-tasks. A command with `ensure` installs its mason tool on first run (on-demand) before running.
--- A bespoke provider may OVERRIDE any of these on the returned spec (base+extend).
---@param name string
---@param data LvimLangSpecData
---@return table<string, LvimLangCommand>
function M.build_commands(name, data)
    ---@type table<string, LvimLangCommand>
    local cmds = {}
    for sub, c in pairs(data.commands or {}) do
        local label = table.concat(c.cmd, " ")
        cmds[sub] = {
            desc = c.desc or label,
            impl = function(args, ctx)
                local root = ctx.root or (vim.uv.cwd() or ".")
                local tool = c.tool or c.cmd[1]
                local function go(bin)
                    local argv = vim.deepcopy(c.cmd)
                    argv[1] = bin or toolchain.resolve(name, tool, root) or argv[1]
                    -- Token substitution: `${file}` → the current buffer's path, `${dir}` → the root, so a
                    -- data command can target the file it was run from (run/check/test-file on ${file}).
                    local file = vim.api.nvim_buf_get_name(ctx.bufnr or vim.api.nvim_get_current_buf())
                    for i = 2, #argv do
                        if argv[i] == "${file}" then
                            argv[i] = file
                        elseif argv[i] == "${dir}" then
                            argv[i] = root
                        end
                    end
                    vim.list_extend(argv, args or {})
                    runner.run(name, {
                        name = label,
                        cmd = argv,
                        cwd = root,
                        group = c.group or "Run",
                        matcher = c.matcher,
                    })
                end
                if c.ensure and c.ensure.mason then
                    require("lvim-lang.core.ensure").tool(c.ensure.mason, c.ensure.bin, function(binpath)
                        go(binpath)
                    end)
                else
                    go(nil)
                end
            end,
        }
    end
    -- Every provider gets the run-config picker, like the bespoke ones (unless it defined its own).
    cmds.config = cmds.config
        or { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" }
    return cmds
end

--- Build the LvimLangProvider spec + its config defaults from a data record. The spec is a plain mutable
--- table so a bespoke caller can extend it before register().
---@param data LvimLangSpecData
---@return LvimLangProvider spec, table defaults
function M.build(data)
    assert(type(data) == "table" and data.name, "declarative.build: data.name required")
    local name = data.name

    -- Config seed. bin_paths / version_manager drive the shared detect strategies; lsp / ft / icons are
    -- the live catalog core.catalog reads. All fully overridable through setup({ providers = { [name] = … } }).
    local defaults = {
        bin_paths = {},
        version_manager = nil,
        lsp = vim.deepcopy(data.lsp or {}),
        ft = vim.deepcopy(data.ft or {}),
        tools = vim.deepcopy(data.tools or {}),
        dap = data.dap, -- kept by ref (a compact DAP spec may carry inline adapter functions)
        icons = vim.deepcopy(data.icons or {}),
    }

    local toolchain_spec = build_toolchain(name, data)

    -- Requirements: every runtime marked `require` with a label (the LSP/tools install through lvim-pkg,
    -- but the runtimes do not — surface each absence with a hint instead of an opaque server crash).
    local req_list = {}
    for _, rt in ipairs(runtimes_of(data)) do
        if rt.require and rt.label then
            req_list[#req_list + 1] = rt
        end
    end
    local reqs
    if #req_list > 0 then
        reqs = function(root)
            local out = {}
            for _, rt in ipairs(req_list) do
                local r = requirements.tool_present(
                    name,
                    rt.key or rt.bin,
                    rt.label,
                    rt.hint or ("Install " .. rt.bin .. " and put it on PATH (or manage it with mise / asdf / SDKMAN)."),
                    root
                )
                r.severity = rt.severity or "warn"
                out[#out + 1] = r
            end
            return out
        end
    end

    -- Health: report each toolchain tool's resolution (+ version), then the provider's requirements.
    local function health(h)
        local root = vim.uv.cwd() or "."
        local keys = vim.tbl_keys(toolchain_spec.tools)
        table.sort(keys)
        for _, tool in ipairs(keys) do
            local path = toolchain.resolve(name, tool, root)
            if path then
                local ver = toolchain.version(name, tool, root)
                h.ok(("%s: %s%s"):format(tool, path, ver and ("  (" .. ver .. ")") or ""))
            else
                h.info(("%s not found — install via the mason registry (:LvimInstaller) or PATH"):format(tool))
            end
        end
        requirements.health(name, root, h)
    end

    -- Statusline: the provider icon + the active run config (only when an icon is configured).
    local has_icon = (data.icons or {}).statusline ~= nil
    local function statusline(root)
        local ic = (config.providers[name] and config.providers[name].icons) or {}
        local parts = {}
        if ic.statusline and ic.statusline ~= "" then
            parts[#parts + 1] = ic.statusline
        end
        local rc = runcfg.active(root)
        if rc and rc.name then
            parts[#parts + 1] = "➤ " .. rc.name
        end
        return table.concat(parts, "  ")
    end

    ---@type LvimLangProvider
    local spec = {
        name = name,
        filetypes = data.filetypes,
        root_patterns = data.root_patterns,
        toolchain = toolchain_spec,
        commands = M.build_commands(name, data),
        requirements = reqs,
        health = health,
        statusline = has_icon and statusline or nil,
    }

    M.install_server_shims(data)
    return spec, defaults
end

--- Record server ownership and install a package.preload shim per server key so lvim-ls'
--- `require("lvim-lang.servers.<key>")` resolves to the generic server_module — UNLESS a real
--- servers/<key>.lua exists on disk (a bespoke override), which always wins (preload is checked BEFORE
--- the searchers, so it WOULD shadow the file). The on-disk check uses nvim_get_runtime_file, not
--- package.searchpath: Neovim resolves rtp `lua/` modules through its own searcher, so package.path does
--- NOT list them — searchpath would miss every bespoke server file and the shim would wrongly shadow it.
--- Idempotent.
---@param data LvimLangSpecData
---@return nil
function M.install_server_shims(data)
    for key in pairs((data.lsp and data.lsp.servers) or {}) do
        M.owners[key] = data.name
        local mod = DIR_PREFIX .. "." .. key
        local rel = "lua/" .. mod:gsub("%.", "/") .. ".lua"
        local on_disk = #vim.api.nvim_get_runtime_file(rel, false) > 0
        if not on_disk and package.loaded[mod] == nil and package.preload[mod] == nil then
            package.preload[mod] = function()
                return require("lvim-lang.servers._declarative").build(key)
            end
        end
    end
end

--- The lvim-ls server-config table for one server `key`, generated from the owning provider's live
--- catalog (config.providers[name].lsp.servers[key] + the ft efm groups). Binary resolved per root
--- through the toolchain; capabilities from lvim-cmp; formatting handed to efm when a formatter is active.
---@param key string
---@return table
function M.server_module(key)
    local name = M.owners[key]
    assert(name, "lvim-lang.declarative.server_module: no owning provider for server '" .. key .. "'")
    local spec = require("lvim-lang.registry").get(name)
    local patterns = (spec and spec.root_patterns) or { ".git" }
    local popts_dap = (config.providers[name] or {}).dap
    -- Only the PRIMARY server carries the DAP spec (so it registers once, not per multi-LSP server).
    local is_primary = catalog.chosen_servers(name)[1] == key
    return {
        -- Per-filetype formatter/linter routing (chosen tools only; empty when none selected).
        efm = catalog.efm_groups(name),
        -- Debugging: the compact DATA.dap expanded to { adapters, configurations }, resolved per root.
        dap = (popts_dap and is_primary)
                and require("lvim-lang.core.dap").build(name, popts_dap, current_root(patterns))
            or nil,
        lsp = {
            root_patterns = patterns,
            --- Built fresh per root so the server binary tracks a project-pinned toolchain.
            ---@return table
            config = function()
                local root = current_root(patterns)
                local popts = config.providers[name] or {}
                local se = ((popts.lsp or {}).servers or {})[key] or {}
                local bin = toolchain.resolve(name, key, root) or se.bin or se.mason or key
                -- An explicit multi-word `cmd` (e.g. { "nu", "--lsp" }) has its head re-resolved; else `{ bin }`.
                local cmd = se.cmd and vim.deepcopy(se.cmd) or { bin }
                if se.cmd then
                    cmd[1] = toolchain.resolve(name, key, root) or cmd[1]
                end
                local cfg = {
                    cmd = cmd,
                    filetypes = se.filetypes or (spec and spec.filetypes),
                    capabilities = capabilities(),
                    on_attach = catalog.lsp_on_attach(name, key),
                }
                -- Only send settings / init_options when non-empty: an empty Lua table encodes as a JSON
                -- ARRAY ([]), which servers reject.
                local settings = se.settings and vim.deepcopy(se.settings) or {}
                if next(settings) then
                    cfg.settings = settings
                end
                if se.init_options and next(se.init_options) then
                    cfg.init_options = se.init_options
                end
                return cfg
            end,
        },
    }
end

return M
