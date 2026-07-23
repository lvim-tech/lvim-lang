-- lvim-lang.providers.swift.deps: SwiftPM dependency commands, run through lvim-tasks.
-- resolve / update / describe / show-dependencies build from ONE spec, so runs land in the lvim-tasks
-- panel / history / dock with the correct `swift` binary (resolved per project through core.toolchain)
-- and cwd (the package root). core.runner runs `:checktime` on exit, so an edited Package.resolved
-- reloads in open buffers.
--
---@module "lvim-lang.providers.swift.deps"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

-- The `:LvimLang deps <sub>` subcommands (argv after `swift`). All arg-less → also lvim-tasks templates.
---@type table<string, { args: string[], label: string, desc: string }>
local SUBS = {
    resolve = {
        args = { "package", "resolve" },
        label = "swift package resolve",
        desc = "Resolve and download the package dependencies",
    },
    update = {
        args = { "package", "update" },
        label = "swift package update",
        desc = "Update the package dependencies to their latest eligible versions",
    },
    describe = {
        args = { "package", "describe" },
        label = "swift package describe",
        desc = "Describe the current package",
    },
    ["show-dependencies"] = {
        args = { "package", "show-dependencies" },
        label = "swift package show-dependencies",
        desc = "Print the resolved dependency graph",
    },
}

local M = {}

--- Resolve the SwiftPM package root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "Package.swift", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `swift <argv…>` for a root through lvim-tasks (Dependencies group).
---@param root string
---@param argv string[]
---@param name string
---@return nil
local function run_swift(root, argv, name)
    local swift = toolchain.resolve("swift", "swift", root) or "swift"
    local cmd = { swift }
    vim.list_extend(cmd, argv)
    runner.run("swift", { name = name, cmd = cmd, cwd = root, group = "Dependencies" })
end

-- lvim-tasks templates (via the provider's `tasks` field): the arg-less subcommands, each applying
-- only in a SwiftPM package (Package.swift at the resolved root).
---@type table[]
M.templates = {}
for _, s in pairs(SUBS) do
    M.templates[#M.templates + 1] = {
        name = s.label,
        desc = s.desc,
        group = "Dependencies",
        builder = function(ctx)
            local root = (ctx and ctx.root) or resolve_root()
            if vim.fn.filereadable(root .. "/Package.swift") ~= 1 then
                return nil
            end
            local swift = toolchain.resolve("swift", "swift", root) or "swift"
            local cmd = { swift }
            vim.list_extend(cmd, s.args)
            return { name = s.label, cmd = cmd, cwd = root, group = "Dependencies" }
        end,
    }
end

--- The `deps` subcommand names (for command completion).
---@return string[]
function M.subs()
    local names = vim.tbl_keys(SUBS)
    table.sort(names)
    return names
end

--- The `:LvimLang deps <sub> [args…]` command: `swift package <resolve|update|describe|show-dependencies>`.
---@param args string[]
---@param ctx table
---@return nil
function M.command(args, ctx)
    local sub = args[1] or "resolve"
    local s = SUBS[sub]
    if not s then
        vim.notify(
            "lvim-lang: usage — :LvimLang deps <" .. table.concat(M.subs(), "|") .. ">",
            vim.log.levels.INFO,
            TITLE
        )
        return
    end
    local root = ctx.root or resolve_root()
    local argv = vim.list_extend(vim.deepcopy(s.args), { unpack(args, 2) })
    run_swift(root, argv, s.label)
end

--- The `:LvimLang update` command: `swift package update` (all dependencies).
---@param _args string[]
---@param ctx table
---@return nil
function M.update(_args, ctx)
    run_swift(ctx.root or resolve_root(), { "package", "update" }, "swift package update")
end

return M
