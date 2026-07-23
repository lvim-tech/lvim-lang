-- lvim-lang.scripts.validate: static validation harness for declarative providers.
-- For each declarative data file (providers/registry/<lang>.lua) it re-loads the record and asserts the
-- factory can turn it into a coherent provider WITHOUT starting any server: the spec has the required
-- shape, the LSP catalog is self-consistent (every `default`/`server` key exists, every server key is
-- resolvable through the toolchain), the generic server-config module builds (cmd + lsp.config), the efm
-- groups build, and each command carries a non-empty argv. Detection only — nothing is installed or run.
--
-- Run headless (after require("lvim-lang").setup({})):
--   :lua =require("lvim-lang.scripts.validate").run()
-- or from a shell smoke test (see the module's run() return: { ok = boolean, problems = string[] }).
--
---@module "lvim-lang.scripts.validate"

local declarative = require("lvim-lang.core.declarative")
local catalog = require("lvim-lang.core.catalog")
local registry_loader = require("lvim-lang.providers.registry")

local M = {}

--- Validate one declarative data record; append human-readable problems to `problems`.
---@param data any
---@param lang string   the data-file name (for messages)
---@param problems string[]
---@return nil
local function check_one(data, lang, problems)
    local function bad(msg)
        problems[#problems + 1] = ("[%s] %s"):format(lang, msg)
    end

    if type(data) ~= "table" then
        return bad("data file did not return a table")
    end
    if type(data.name) ~= "string" or data.name == "" then
        return bad("missing name")
    end
    local name = data.name
    if type(data.filetypes) ~= "table" or #data.filetypes == 0 then
        bad("filetypes must be a non-empty list")
    end
    if type(data.root_patterns) ~= "table" or #data.root_patterns == 0 then
        bad("root_patterns must be a non-empty list")
    end

    -- Build must not error and must yield a coherent spec.
    local ok, spec = pcall(declarative.build, data)
    if not ok then
        return bad("declarative.build errored: " .. tostring(spec))
    end
    if type(spec.commands) ~= "table" then
        bad("build produced no commands table")
    end
    if spec.toolchain == nil or type(spec.toolchain.tools) ~= "table" then
        bad("build produced no toolchain.tools")
    end

    -- LSP catalog self-consistency.
    local servers = (data.lsp and data.lsp.servers) or {}
    local default = data.lsp and data.lsp.default
    local defaults = type(default) == "string" and { default } or (default or {})
    if data.lsp and #defaults == 0 then
        bad("lsp declared but no `default` server chosen")
    end
    for _, key in ipairs(defaults) do
        if not servers[key] then
            bad(("lsp.default '%s' has no entry in lsp.servers"):format(key))
        end
    end
    for key, se in pairs(servers) do
        if se.mason and not spec.toolchain.tools[key] then
            bad(("server '%s' has no toolchain strategy (unresolvable binary)"):format(key))
        end
        -- The generic server-config module must build and expose an lsp.config function.
        local mok, mod = pcall(declarative.server_module, key)
        if not mok then
            bad(("server_module('%s') errored: %s"):format(key, tostring(mod)))
        elseif type(mod) ~= "table" or type(mod.lsp) ~= "table" or type(mod.lsp.config) ~= "function" then
            bad(("server_module('%s') is missing lsp.config"):format(key))
        end
    end

    -- Chosen servers (as the LSP fan-out will see them) must be non-empty when an LSP is declared.
    if data.lsp and #catalog.chosen_servers(name) == 0 then
        bad("catalog.chosen_servers returned empty despite an lsp catalog")
    end

    -- efm groups must build without error.
    local eok, egroups = pcall(catalog.efm_groups, name)
    if not eok then
        bad("catalog.efm_groups errored: " .. tostring(egroups))
    end

    -- Commands: each argv must be a non-empty list of strings.
    for sub, c in pairs(data.commands or {}) do
        if type(c.cmd) ~= "table" or #c.cmd == 0 then
            bad(("command '%s' has an empty/absent cmd"):format(sub))
        else
            for i, part in ipairs(c.cmd) do
                if type(part) ~= "string" then
                    bad(("command '%s' cmd[%d] is not a string"):format(sub, i))
                end
            end
        end
    end
end

--- Validate every declarative data file. Returns a report and prints a summary.
---@return { ok: boolean, problems: string[], count: integer }
function M.run()
    local problems = {}
    local names = registry_loader.data_list()
    for _, lang in ipairs(names) do
        local ok, data = pcall(require, "lvim-lang.providers.registry." .. lang)
        if not ok then
            problems[#problems + 1] = ("[%s] failed to require: %s"):format(lang, tostring(data))
        else
            check_one(data, lang, problems)
        end
    end
    local report = { ok = #problems == 0, problems = problems, count = #names }
    if report.ok then
        print(("lvim-lang validate: OK — %d declarative provider(s) valid"):format(report.count))
    else
        print(("lvim-lang validate: %d problem(s) across %d provider(s):"):format(#problems, report.count))
        for _, p in ipairs(problems) do
            print("  - " .. p)
        end
    end
    return report
end

return M
