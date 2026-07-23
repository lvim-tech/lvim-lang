-- lvim-lang.core.catalog: resolve a provider's per-filetype tool catalog into concrete choices.
-- The canonical provider model (see plan-all-languages.md): one provider covers several filetypes;
-- each ft carries a catalog of formatters / linters / debuggers with a default (or `false` = none),
-- plus an LSP server catalog with a default that may be a STRING or a LIST (multi-LSP). The user
-- picks through config.providers.<name> and this module turns catalog-data + user-choice into:
--   * install_entry() — the lvim-ls language entry (install UNION of the chosen servers' + tools'
--     mason packages) that register_language merges, so lvim-installer offers exactly the selected
--     tools through the existing prompt. formatters/linters go in their buckets, debuggers in theirs,
--     and any non-LSP/fmt/lint/dbg helper in the generic `tools` bucket.
--   * efm_groups() — PER-FILETYPE efm tool groups (gofumpt only on `go`, not `gomod`), for the server
--     config module's `efm` field; efm-langserver routes each tool to its own filetype.
-- Detection/selection only — nothing is installed or started here.
--
---@module "lvim-lang.core.catalog"

local config = require("lvim-lang.config")

local M = {}

--- The provider's live option block (defaults seeded at register, user overrides merged in).
---@param name string
---@return table
local function popts(name)
    return config.providers[name] or {}
end

--- The chosen LSP server keys for a provider: the user's `lsp.server` override (string|string[]),
--- else the catalog `lsp.default`. Always returned as a list; the FIRST is the primary (it carries
--- the install union of the ft tools).
---@param name string
---@return string[]
function M.chosen_servers(name)
    local lsp = popts(name).lsp or {}
    local sel = lsp.server or lsp.default
    if type(sel) == "string" then
        sel = { sel }
    end
    return sel or {}
end

--- The catalog entry for one server key (mason / filetypes / settings / role / …).
---@param name string
---@param key string
---@return table|nil
function M.server_entry(name, key)
    return ((popts(name).lsp or {}).servers or {})[key]
end

--- The provider's declared filetypes (from its registered spec).
---@param name string
---@return string[]
function M.provider_filetypes(name)
    local spec = require("lvim-lang.registry").get(name)
    return (spec and spec.filetypes) or {}
end

--- The chosen tool KEY for a (filetype, kind): the user's explicit `ft.<ft>.<kind>` pick (a key or
--- `false` = none), else the ft block's `defaults.<kind>`. Returns nil when none is selected.
---@param name string
---@param ft string
---@param kind "formatter"|"linter"|"debugger"
---@return string|nil
function M.chosen_tool(name, ft, kind)
    local ftblock = (popts(name).ft or {})[ft] or {}
    local sel = ftblock[kind]
    if sel == nil then
        sel = (ftblock.defaults or {})[kind]
    end
    if sel == false or sel == nil then
        return nil
    end
    return sel
end

--- The catalog entry for a (filetype, kind, key) — { mason, bin?, efm?, dap?, settings? }.
---@param name string
---@param ft string
---@param kind "formatter"|"linter"|"debugger"
---@param key string
---@return table|nil
local function tool_entry(name, ft, kind, key)
    local ftblock = (popts(name).ft or {})[ft] or {}
    return (ftblock[kind .. "s"] or {})[key]
end

--- Append a mason tool to a language-entry list (a string, or { name, bin = … } when the binary name
--- differs), de-duplicated by mason name.
---@param list table
---@param seen table<string, boolean>
---@param mason string|nil
---@param bin string|nil
---@return nil
local function add_tool(list, seen, mason, bin)
    if not mason or seen[mason] then
        return
    end
    seen[mason] = true
    list[#list + 1] = bin and { mason, bin = bin } or mason
end

--- The INSTALL UNION of a provider's chosen formatters / linters / debuggers across every filetype
--- (each in its own bucket), plus any extra `tools` the provider declares outside those buckets, and
--- the provider's `filetypes`. NO `lsp` — the per-server mason is added per entry in
--- core.lsp.register_catalog (the primary server's entry carries this union). De-duplicated by mason
--- name; entries are strings or `{ name, bin = … }`. Feeds `missing_tools_for_server` → the installer.
---@param name string
---@return { filetypes: string[], formatters: table, linters: table, debuggers: table, tools: table }
function M.union_entry(name)
    local fts = M.provider_filetypes(name)
    local u = { filetypes = fts, formatters = {}, linters = {}, debuggers = {}, tools = {} }
    local seen = { formatters = {}, linters = {}, debuggers = {}, tools = {} }

    for _, ft in ipairs(fts) do
        for kind, bucket in pairs({ formatter = "formatters", linter = "linters", debugger = "debuggers" }) do
            local key = M.chosen_tool(name, ft, kind)
            if key then
                local te = tool_entry(name, ft, kind, key)
                if te then
                    add_tool(u[bucket], seen[bucket], te.mason, te.bin)
                end
            end
        end
    end

    -- Extra helpers a provider lists outside the four buckets (build/test helpers, runtimes…).
    for _, tool in ipairs(popts(name).tools or {}) do
        if type(tool) == "table" then
            add_tool(u.tools, seen.tools, tool.mason or tool[1], tool.bin)
        else
            add_tool(u.tools, seen.tools, tool, nil)
        end
    end

    -- Codegen tools the user marked `active = true` install UPFRONT (they join the `tools` bucket →
    -- the file-open installer popup, like a formatter/linter/debugger). Un-marked codegen tools stay
    -- ON-DEMAND (core.ensure installs them the first time their command runs).
    for _, entry in pairs(popts(name).codegen or {}) do
        if type(entry) == "table" and entry.active then
            add_tool(u.tools, seen.tools, entry.mason, entry.bin)
        end
    end

    return u
end

--- Is an efm formatter active (chosen) for a (provider, filetype)?
---@param name string
---@param ft string
---@return boolean
function M.has_formatter(name, ft)
    return M.chosen_tool(name, ft, "formatter") ~= nil
end

--- Build an LSP `on_attach` that COORDINATES formatting with efm: when an efm formatter is active
--- for the buffer's filetype, the LSP client's own formatting capability is switched off so the two
--- do not both format the buffer (efm owns it). With no formatter chosen, the LSP keeps formatting.
--- Capabilities are per-client, so disabling on the first attach covers every buffer of that client.
--- A provider server-entry `on_attach` (config.providers[name].lsp.servers[key].on_attach) still runs.
---@param name string  provider name
---@param key string   server key (its optional catalog on_attach is composed in)
---@return fun(client: table, bufnr: integer)
function M.lsp_on_attach(name, key)
    return function(client, bufnr)
        local ft = vim.bo[bufnr].filetype
        if M.has_formatter(name, ft) then
            client.server_capabilities.documentFormattingProvider = false
            client.server_capabilities.documentRangeFormattingProvider = false
        end
        local se = M.server_entry(name, key)
        if se and type(se.on_attach) == "function" then
            se.on_attach(client, bufnr)
        end
    end
end

--- PER-FILETYPE efm groups for a provider's server config `efm` field: one group per filetype that
--- has a chosen formatter and/or linter, each tool tagged with its `server_name` (efm de-dups on it)
--- so gofumpt lands on `go` while a go.mod linter lands on `gomod`. Empty groups are omitted.
---@param name string
---@return { filetypes: string[], tools: table[] }[]
function M.efm_groups(name)
    local groups = {}
    for _, ft in ipairs(M.provider_filetypes(name)) do
        local tools = {}
        for _, kind in ipairs({ "formatter", "linter" }) do
            local key = M.chosen_tool(name, ft, kind)
            if key then
                local te = tool_entry(name, ft, kind, key)
                if te and te.efm then
                    tools[#tools + 1] = vim.tbl_extend("force", { server_name = key }, te.efm)
                end
            end
        end
        if #tools > 0 then
            groups[#groups + 1] = { filetypes = { ft }, tools = tools }
        end
    end
    return groups
end

return M
