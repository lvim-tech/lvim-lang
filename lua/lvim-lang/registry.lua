-- lvim-lang.registry: the provider registry + lazy activation.
-- A provider (Dart, Rust, …) calls register() with its LvimLangProvider spec, usually from
-- its own init.lua at plugin load — SELF-registration, the same seam model as
-- lvim-utils.cursor.register: it EXTENDS the registry at runtime and re-arms a single
-- FileType autocmd, so provider load order relative to lvim-lang.setup() does not matter.
--
-- Activation is LAZY and per (root, provider): the first buffer of a registered filetype
-- whose project root has not been activated yet wires that language up ONCE — resolve the
-- root, resolve the toolchain, register the LSP through lvim-lsp, install runner templates,
-- attach decorations, run the provider's on_activate. Untouched filetypes cost nothing.
--
---@module "lvim-lang.registry"

local config = require("lvim-lang.config")
local state = require("lvim-lang.state")

---@class LvimLangProvider
---@field name          string                       Unique id, e.g. "dart"
---@field filetypes     string[]                      Filetypes that activate the provider
---@field root_patterns string[]                      Project-root markers (walked up from the file)
---@field toolchain?    LvimLangToolchainSpec         Toolchain resolution strategies (see core.toolchain)
---@field lsp?          LvimLangLspSpec               LSP registration spec (see core.lsp)
---@field commands?     table<string, LvimLangCommand> Subcommands exposed under :LvimLang
---@field tasks?        table[]                       lvim-tasks templates to register
---@field decorations?  LvimLangDecorationSpec[]      Notification→decoration specs (see core.decorations)
---@field outline?      LvimLangOutlineSpec           Alternative outline source (see core.outline)
---@field dap?          table                         lvim-dap adapter/configuration spec
---@field pkg?          fun(ft: string): table[]      Extra lvim-pkg items (toolchain/SDK deps)
---@field health?       fun(h: table)                 Per-provider :checkhealth section
---@field statusline?   fun(root: string): string     Statusline segment builder
---@field on_activate?  fun(root: string, bufnr: integer) First-buffer-in-root hook

---@class LvimLangCommand
---@field impl     fun(args: string[], ctx: table)    Command body
---@field complete? fun(arg: string, line: string): string[] Completion for the subcommand
---@field desc?    string                              One-line description

---@type table<string, LvimLangProvider>
local providers = {}

---@type table<string, string>   filetype → provider name
local ft_index = {}

---@type integer|nil
local augroup = nil

--- Resolve the project root for a buffer using the provider's root patterns; falls back to
--- the buffer file's directory, then cwd, so activation always has a stable key.
---@param bufnr integer
---@param patterns string[]
---@return string
local function resolve_root(bufnr, patterns)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        local found = vim.fs.root(bufnr, patterns)
        if found then
            return found
        end
        return vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Per-ROOT activation, exactly once per root. Provider-level wiring (LSP, task templates) is
--- done once at register() time — lvim-ls/lvim-tasks then handle each buffer/root themselves —
--- so this hook is only for genuinely per-root work (a provider's on_activate).
---@param provider LvimLangProvider
---@param root string
---@param bufnr integer
---@return nil
local function activate(provider, root, bufnr)
    if state.roots[root] then
        return
    end
    state.roots[root] = true
    if provider.on_activate then
        provider.on_activate(root, bufnr)
    end
end

--- The FileType callback: find the provider for the event buffer's filetype and lazily
--- activate its root. Cheap for unregistered filetypes (a single table lookup).
---@param args table  autocmd callback args ({ buf = … })
---@return nil
local function on_filetype(args)
    if not config.enabled then
        return
    end
    local ft = vim.bo[args.buf].filetype
    local name = ft_index[ft]
    if not name then
        return
    end
    local provider = providers[name]
    local root = resolve_root(args.buf, provider.root_patterns or {})
    activate(provider, root, args.buf)
end

--- (Re)arm the single FileType autocmd covering every registered filetype. Called on each
--- register() so a provider that loads AFTER setup() still gets activated (runtime-extend,
--- like cursor.register — never a full teardown of live state).
---@return nil
local function rearm()
    augroup = vim.api.nvim_create_augroup("lvim_lang_registry", { clear = true })
    local fts = vim.tbl_keys(ft_index)
    if #fts == 0 then
        return
    end
    vim.api.nvim_create_autocmd("FileType", {
        group = augroup,
        pattern = fts,
        callback = on_filetype,
        desc = "lvim-lang: lazily activate the language provider for this buffer",
    })
end

local M = {}

---@param spec LvimLangProvider
---@param defaults? table
---@return nil
function M.register(spec, defaults)
    assert(type(spec) == "table" and spec.name, "lvim-lang.registry.register: spec.name required")
    providers[spec.name] = spec
    for _, ft in ipairs(spec.filetypes or {}) do
        ft_index[ft] = spec.name
    end
    if defaults then
        -- Seed defaults as the BASE, then re-apply whatever the user already set via setup() so
        -- USER OPTIONS WIN (setup merges user opts into config.providers[name] before the provider
        -- loads; merging defaults directly on top would clobber them). Everything a provider
        -- declares is therefore fully overridable.
        local merge = require("lvim-utils.utils").merge
        local seeded = vim.deepcopy(defaults)
        merge(seeded, config.providers[spec.name] or {})
        config.providers[spec.name] = seeded
    end
    -- One-time provider wiring, AFTER the config defaults are seeded (so the server config and
    -- task templates read effective options). Both bridges are additive and idempotent; the
    -- engines (lvim-ls, lvim-tasks) then handle each buffer/root/run themselves.
    if spec.lsp then
        require("lvim-lang.core.lsp").register(spec.lsp)
    end
    if spec.tasks then
        require("lvim-lang.core.runner").register_templates(spec.tasks)
    end
    if spec.decorations then
        local decorations = require("lvim-lang.core.decorations")
        for _, deco in ipairs(spec.decorations) do
            decorations.register(deco)
        end
    end
    if spec.outline then
        require("lvim-lang.core.outline").register(spec.outline)
    end
    rearm()
end

--- The provider registered under `name`, or nil.
---@param name string
---@return LvimLangProvider|nil
function M.get(name)
    return providers[name]
end

--- Every registered provider name (for :checkhealth / status / commands).
---@return string[]
function M.names()
    return vim.tbl_keys(providers)
end

--- The active provider for a buffer (by its filetype) and that buffer's resolved root.
---@param bufnr? integer
---@return LvimLangProvider|nil provider, string|nil root
function M.for_buffer(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local name = ft_index[vim.bo[bufnr].filetype]
    if not name then
        return nil, nil
    end
    local provider = providers[name]
    return provider, resolve_root(bufnr, provider.root_patterns or {})
end

return M
