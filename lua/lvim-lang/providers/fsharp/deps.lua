-- lvim-lang.providers.fsharp.deps: NuGet dependency commands, run through lvim-tasks.
-- add / remove / restore / list build from ONE spec builder, so runs land in the lvim-tasks panel /
-- history / dock with the correct `dotnet` binary (resolved per project through core.toolchain) and
-- cwd (the project/solution root). core.runner runs `:checktime` on exit, so an edited `.fsproj` /
-- lockfile reloads in open buffers. The arg-less subcommands (`restore`, `list`) also register as
-- lvim-tasks templates.
--
---@module "lvim-lang.providers.fsharp.deps"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

-- The `:LvimLang deps <sub>` subcommands (argv after `dotnet`). Arg-less → also lvim-tasks templates.
---@type table<string, { args: string[], label: string, desc: string }>
local SUBS = {
    restore = { args = { "restore" }, label = "dotnet restore", desc = "Restore NuGet dependencies" },
    list = { args = { "list", "package" }, label = "dotnet list package", desc = "List referenced NuGet packages" },
}

local M = {}

--- Whether a directory entry name is an F# project-root marker (a solution / project file, the paket
--- manifest, or `.git`).
---@param name string
---@return boolean
local function is_root_marker(name)
    return name:match("%.sln$") ~= nil
        or name:match("%.fsproj$") ~= nil
        or name == "paket.dependencies"
        or name == ".git"
end

--- Resolve the .NET project/solution root for the current buffer (nearest `.sln`/`.fsproj`/
--- `paket.dependencies`, else `.git`, else the file's directory, else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, is_root_marker) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `dotnet <argv…>` for a root through lvim-tasks (Dependencies group, `typescript` .NET matcher).
---@param root string
---@param argv string[]
---@param name string
---@return nil
local function run_dotnet(root, argv, name)
    local dotnet = toolchain.resolve("fsharp", "dotnet", root) or "dotnet"
    local cmd = { dotnet }
    vim.list_extend(cmd, argv)
    runner.run("fsharp", { name = name, cmd = cmd, cwd = root, group = "Dependencies", matcher = "typescript" })
end

-- lvim-tasks templates (via the provider's `tasks` field): the arg-less subcommands, each applying
-- only in a .NET project (a `.sln`/`.fsproj`/`paket.dependencies` at or above the resolved root).
---@type table[]
M.templates = {}
for sub, s in pairs(SUBS) do
    M.templates[#M.templates + 1] = {
        name = s.label,
        desc = s.desc,
        group = "Dependencies",
        builder = function(ctx)
            local root = (ctx and ctx.root) or resolve_root()
            local buf = vim.api.nvim_get_current_buf()
            if vim.api.nvim_buf_get_name(buf) ~= "" and not vim.fs.root(buf, is_root_marker) then
                return nil
            end
            local dotnet = toolchain.resolve("fsharp", "dotnet", root) or "dotnet"
            local cmd = { dotnet }
            vim.list_extend(cmd, s.args)
            return { name = s.label, cmd = cmd, cwd = root, group = "Dependencies", matcher = "typescript" }
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

--- The `:LvimLang deps <sub> [args…]` command: `dotnet <restore|list package>` through lvim-tasks.
---@param args string[]
---@param ctx table
---@return nil
function M.command(args, ctx)
    local sub = args[1] or "restore"
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
    run_dotnet(root, argv, s.label)
end

--- The `:LvimLang add <package[@version]> [args]` command: `dotnet add package`. A trailing
--- `@version` is translated to `--version <v>` (dotnet's own flag).
---@param args string[]
---@param ctx table
---@return nil
function M.add(args, ctx)
    if #args == 0 then
        vim.notify("lvim-lang: usage — :LvimLang add <package[@version]> [args]", vim.log.levels.INFO, TITLE)
        return
    end
    local pkg, version = args[1]:match("^(.-)@(.+)$")
    local argv = { "add", "package", pkg or args[1] }
    if version then
        argv[#argv + 1] = "--version"
        argv[#argv + 1] = version
    end
    for i = 2, #args do
        argv[#argv + 1] = args[i]
    end
    run_dotnet(ctx.root or resolve_root(), argv, "dotnet add package " .. (pkg or args[1]))
end

--- The `:LvimLang remove <package>` command: `dotnet remove package`.
---@param args string[]
---@param ctx table
---@return nil
function M.remove(args, ctx)
    if #args == 0 then
        vim.notify("lvim-lang: usage — :LvimLang remove <package>", vim.log.levels.INFO, TITLE)
        return
    end
    run_dotnet(
        ctx.root or resolve_root(),
        vim.list_extend({ "remove", "package" }, args),
        "dotnet remove package " .. args[1]
    )
end

--- The `:LvimLang restore [args]` command: `dotnet restore`.
---@param args string[]
---@param ctx table
---@return nil
function M.restore(args, ctx)
    run_dotnet(ctx.root or resolve_root(), vim.list_extend({ "restore" }, args), "dotnet restore")
end

return M
