-- lvim-lang.providers.registry: the declarative-provider loader (the long tail, Tier 2/3/4).
-- Iterates the data files (providers/registry/<lang>.lua, each a LvimLangSpecData), builds a full
-- provider from each through core.declarative, and registers it — the mass-registration seam so a new
-- declarative language is a data file plus one line in DATA, with zero new Lua logic. core.declarative
-- installs the package.preload server-config shims as part of build(), so no servers/<key>.lua is owed.
--
-- Loaded once by lvim-lang.setup(), AFTER the bespoke BUILTIN_PROVIDERS, honouring config.disable the
-- same way (a disabled name is left free for a user override).
--
---@module "lvim-lang.providers.registry"

local declarative = require("lvim-lang.core.declarative")
local registry = require("lvim-lang.registry")

local M = {}

-- Declarative data files to load (each providers/registry/<name>.lua). Grows as Tier 2/3/4 ships.
---@type string[]
local DATA = {
    "lua",
    -- Wave 4 Tier 2 — batch 1 (restores the archived nvim-config shell / r / perl / d languages + Julia).
    "bash",
    "r",
    "perl",
    "d",
    "julia",
}

--- The declarative data-file names (for the validate harness / tooling).
---@return string[]
function M.data_list()
    return vim.deepcopy(DATA)
end

--- Build + register one declarative provider from its data record.
---@param data LvimLangSpecData
---@return nil
function M.load(data)
    local spec, defaults = declarative.build(data)
    registry.register(spec, defaults)
end

--- Load every declarative data file except disabled names.
---@param disabled? table<string, boolean>  provider names to skip (from config.disable)
---@return nil
function M.setup(disabled)
    disabled = disabled or {}
    for _, lang in ipairs(DATA) do
        if not disabled[lang] then
            local ok, data = pcall(require, "lvim-lang.providers.registry." .. lang)
            if ok and type(data) == "table" then
                M.load(data)
            else
                vim.notify(
                    ("lvim-lang: failed to load declarative provider '%s'%s"):format(
                        lang,
                        type(data) == "string" and (": " .. data) or ""
                    ),
                    vim.log.levels.WARN,
                    { title = "lvim-lang" }
                )
            end
        end
    end
end

return M
