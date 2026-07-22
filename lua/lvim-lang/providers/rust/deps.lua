-- lvim-lang.providers.rust.deps: Cargo dependency commands, run through lvim-tasks.
-- add / remove / update / tree / fetch build from ONE spec builder, so runs land in the lvim-tasks
-- panel / history / dock with the correct `cargo` binary (resolved per project through
-- core.toolchain) and cwd (the crate root). core.runner runs `:checktime` on exit, so an edited
-- Cargo.toml / Cargo.lock reloads in open buffers.
--
---@module "lvim-lang.providers.rust.deps"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

-- The `:LvimLang deps <sub>` subcommands (argv after `cargo`). All arg-less → also lvim-tasks templates.
---@type table<string, { args: string[], label: string, desc: string }>
local SUBS = {
    update = { args = { "update" }, label = "cargo update", desc = "Update dependencies (respecting semver)" },
    tree = { args = { "tree" }, label = "cargo tree", desc = "Print the dependency tree" },
    fetch = { args = { "fetch" }, label = "cargo fetch", desc = "Fetch dependencies into the cache" },
}

local M = {}

--- Resolve the Cargo crate root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "Cargo.toml", "Cargo.lock", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `cargo <argv…>` for a root through lvim-tasks (Dependencies group, `rust` matcher).
---@param root string
---@param argv string[]
---@param name string
---@return nil
local function run_cargo(root, argv, name)
    local cargo = toolchain.resolve("rust", "cargo", root) or "cargo"
    local cmd = { cargo }
    vim.list_extend(cmd, argv)
    runner.run("rust", { name = name, cmd = cmd, cwd = root, group = "Dependencies", matcher = "rust" })
end

-- lvim-tasks templates (via the provider's `tasks` field): the arg-less subcommands, each applying
-- only in a Cargo project (Cargo.toml at the resolved root).
---@type table[]
M.templates = {}
for sub, s in pairs(SUBS) do
    M.templates[#M.templates + 1] = {
        name = s.label,
        desc = s.desc,
        group = "Dependencies",
        builder = function(ctx)
            local root = (ctx and ctx.root) or resolve_root()
            if vim.fn.filereadable(root .. "/Cargo.toml") ~= 1 then
                return nil
            end
            local cargo = toolchain.resolve("rust", "cargo", root) or "cargo"
            local cmd = { cargo }
            vim.list_extend(cmd, s.args)
            return { name = s.label, cmd = cmd, cwd = root, group = "Dependencies", matcher = "rust" }
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

--- The `:LvimLang deps <sub> [args…]` command: `cargo <update|tree|fetch>` through lvim-tasks.
---@param args string[]
---@param ctx table
---@return nil
function M.command(args, ctx)
    local sub = args[1] or "tree"
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
    run_cargo(root, argv, s.label)
end

--- The `:LvimLang add <crate[@version]> [--features …]` command: `cargo add`.
---@param args string[]
---@param ctx table
---@return nil
function M.add(args, ctx)
    if #args == 0 then
        vim.notify("lvim-lang: usage — :LvimLang add <crate[@version]> [--features …]", vim.log.levels.INFO, TITLE)
        return
    end
    run_cargo(ctx.root or resolve_root(), vim.list_extend({ "add" }, args), "cargo add " .. args[1])
end

--- The `:LvimLang remove <crate…>` command: `cargo remove`.
---@param args string[]
---@param ctx table
---@return nil
function M.remove(args, ctx)
    if #args == 0 then
        vim.notify("lvim-lang: usage — :LvimLang remove <crate…>", vim.log.levels.INFO, TITLE)
        return
    end
    run_cargo(ctx.root or resolve_root(), vim.list_extend({ "remove" }, args), "cargo remove " .. args[1])
end

--- The `:LvimLang update [crate]` command: `cargo update` (all, or a single crate).
---@param args string[]
---@param ctx table
---@return nil
function M.update(args, ctx)
    run_cargo(ctx.root or resolve_root(), vim.list_extend({ "update" }, args), "cargo update")
end

return M
