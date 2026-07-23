-- lvim-lang.providers.elixir.deps: Hex / mix dependency commands, run through lvim-tasks.
-- get / update / tree / clean / unlock build from ONE spec table, so runs land in the lvim-tasks panel
-- / history / dock with the correct `mix` binary (resolved per project through core.toolchain) and cwd
-- (the project root). core.runner runs `:checktime` on exit, so an edited mix.lock reloads in open
-- buffers. Unlike Cargo / Bundler, mix has NO `add` / `remove` verb — dependencies are declared by
-- hand in `mix.exs`'s `deps/0` — so only the lifecycle verbs are exposed (no add/remove commands).
--
---@module "lvim-lang.providers.elixir.deps"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

-- The `:LvimLang deps <sub>` subcommands (argv after `mix`). The arg-less ones (get / tree) also become
-- lvim-tasks templates. mix's dependency tasks use the dotted form (`deps.get`, `deps.tree`, …).
---@type table<string, { args: string[], label: string, desc: string, template?: boolean }>
local SUBS = {
    get = { args = { "deps.get" }, label = "mix deps.get", desc = "Fetch the project's dependencies", template = true },
    update = {
        args = { "deps.update", "--all" },
        label = "mix deps.update",
        desc = "Update dependencies to the latest allowed",
    },
    tree = { args = { "deps.tree" }, label = "mix deps.tree", desc = "Print the dependency tree", template = true },
    clean = {
        args = { "deps.clean", "--all" },
        label = "mix deps.clean",
        desc = "Delete the build artifacts of dependencies",
    },
    unlock = {
        args = { "deps.unlock", "--all" },
        label = "mix deps.unlock",
        desc = "Unlock dependencies (clear mix.lock entries)",
    },
}

local M = {}

--- Resolve the Elixir project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "mix.exs", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `mix <argv…>` for a root through lvim-tasks (Dependencies group, `generic` matcher).
---@param root string
---@param argv string[]
---@param name string
---@return nil
local function run_mix(root, argv, name)
    local mix = toolchain.resolve("elixir", "mix", root) or "mix"
    local cmd = { mix }
    vim.list_extend(cmd, argv)
    runner.run("elixir", { name = name, cmd = cmd, cwd = root, group = "Dependencies", matcher = "generic" })
end

-- lvim-tasks templates (via the provider's `tasks` field): the arg-less subcommands, each applying
-- only in a mix project (mix.exs at the resolved root).
---@type table[]
M.templates = {}
for _, sub in ipairs({ "get", "tree" }) do
    local s = SUBS[sub]
    M.templates[#M.templates + 1] = {
        name = s.label,
        desc = s.desc,
        group = "Dependencies",
        builder = function(ctx)
            local root = (ctx and ctx.root) or resolve_root()
            if vim.fn.filereadable(vim.fs.joinpath(root, "mix.exs")) ~= 1 then
                return nil
            end
            local mix = toolchain.resolve("elixir", "mix", root) or "mix"
            local cmd = { mix }
            vim.list_extend(cmd, s.args)
            return { name = s.label, cmd = cmd, cwd = root, group = "Dependencies", matcher = "generic" }
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

--- The `:LvimLang deps <get|update|tree|clean|unlock> [args…]` command: `mix deps.<sub>` through
--- lvim-tasks.
---@param args string[]
---@param ctx table
---@return nil
function M.command(args, ctx)
    local sub = args[1] or "get"
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
    run_mix(root, argv, s.label)
end

return M
