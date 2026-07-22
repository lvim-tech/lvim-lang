-- lvim-lang.providers.typescript.pm: package-manager + package.json script detection.
-- The JS/TS ecosystem's project-specific concern (the analog of Python's venv): which package
-- manager a project uses (npm / pnpm / yarn / bun) and which scripts its package.json defines. The
-- manager is detected from the lockfile (or the corepack `packageManager` field), unless pinned via
-- `providers.typescript.package_manager`; the scripts feed the `:LvimLang script` picker and the run
-- tasks. Detection only — pure reads of the project files.
--
---@module "lvim-lang.providers.typescript.pm"

local config = require("lvim-lang.config")
local ui = require("lvim-lang.core.ui")

local M = {}

-- Lockfile → manager, in PRIORITY order (a repo may carry more than one).
---@type { file: string, manager: string }[]
local LOCKS = {
    { file = "pnpm-lock.yaml", manager = "pnpm" },
    { file = "bun.lockb", manager = "bun" },
    { file = "bun.lock", manager = "bun" },
    { file = "yarn.lock", manager = "yarn" },
    { file = "package-lock.json", manager = "npm" },
}

--- The parsed package.json for a root, or nil (absent / invalid JSON).
---@param root string
---@return table|nil
function M.package_json(root)
    local path = vim.fs.joinpath(root, "package.json")
    if vim.fn.filereadable(path) ~= 1 then
        return nil
    end
    local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
    return (ok and type(data) == "table") and data or nil
end

--- The package manager for a root: the pinned `package_manager` (unless "auto"), else the lockfile,
--- else the corepack `packageManager` field, else npm.
---@param root string
---@return string
function M.detect(root)
    local pinned = (config.providers.typescript or {}).package_manager
    if type(pinned) == "string" and pinned ~= "auto" then
        return pinned
    end
    for _, l in ipairs(LOCKS) do
        if vim.fn.filereadable(vim.fs.joinpath(root, l.file)) == 1 then
            return l.manager
        end
    end
    local pkg = M.package_json(root)
    if pkg and type(pkg.packageManager) == "string" then
        local name = pkg.packageManager:match("^(%a+)@")
        if name then
            return name
        end
    end
    return "npm"
end

--- The `scripts` table of a root's package.json as an ordered list ({ name, cmd }); empty when none.
---@param root string
---@return { name: string, cmd: string }[]
function M.scripts(root)
    local pkg = M.package_json(root)
    if not pkg or type(pkg.scripts) ~= "table" then
        return {}
    end
    local names = vim.tbl_keys(pkg.scripts)
    table.sort(names)
    local list = {}
    for _, name in ipairs(names) do
        list[#list + 1] = { name = name, cmd = pkg.scripts[name] }
    end
    return list
end

--- Pick a package.json script through the canonical picker; `cb(name)` on confirm (nil on cancel).
---@param root string
---@param cb fun(name: string|nil)
---@return nil
function M.pick_script(root, cb)
    local scripts = M.scripts(root)
    if #scripts == 0 then
        vim.notify("lvim-lang: no scripts in package.json", vim.log.levels.INFO, { title = "lvim-lang" })
        cb(nil)
        return
    end
    local ic = (config.providers.typescript or {}).icons or {}
    local items = {}
    for i, s in ipairs(scripts) do
        items[i] = { label = ("%s   %s"):format(s.name, s.cmd), icon = ic.script or "󰜎", name = s.name }
    end
    ui.pick({ title = "package.json scripts", items = items }, function(item)
        cb(item and item.name or nil)
    end)
end

return M
