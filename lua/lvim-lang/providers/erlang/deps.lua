-- lvim-lang.providers.erlang.deps: rebar3 dependency commands, run through lvim-tasks.
-- get / upgrade / tree build from ONE spec table, so runs land in the lvim-tasks panel / history /
-- dock with the correct `rebar3` binary (resolved per project through core.toolchain) and cwd (the
-- project root). core.runner runs `:checktime` on exit, so an edited rebar.lock reloads in open
-- buffers. Dependencies are declared by hand in `rebar.config` (`{deps, [...]}`), so there is no
-- add / remove verb — rebar3 fetches / upgrades what the config declares.
--
---@module "lvim-lang.providers.erlang.deps"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

-- The `:LvimLang deps <sub>` subcommands (argv after `rebar3`). All arg-less → also lvim-tasks templates.
---@type table<string, { args: string[], label: string, desc: string }>
local SUBS = {
    get = { args = { "get-deps" }, label = "rebar3 get-deps", desc = "Fetch the declared dependencies" },
    upgrade = { args = { "upgrade" }, label = "rebar3 upgrade", desc = "Upgrade dependencies (update the lock)" },
    tree = { args = { "tree" }, label = "rebar3 tree", desc = "Print the dependency tree" },
}

local M = {}

--- Resolve the Erlang project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "rebar.config", "erlang.mk", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `rebar3 <argv…>` for a root through lvim-tasks (Dependencies group, `generic` matcher).
---@param root string
---@param argv string[]
---@param name string
---@return nil
local function run_rebar3(root, argv, name)
    local rebar3 = toolchain.resolve("erlang", "rebar3", root) or "rebar3"
    local cmd = { rebar3 }
    vim.list_extend(cmd, argv)
    runner.run("erlang", { name = name, cmd = cmd, cwd = root, group = "Dependencies", matcher = "generic" })
end

-- lvim-tasks templates (via the provider's `tasks` field): the arg-less subcommands, each applying
-- only in a rebar3 project (rebar.config at the resolved root).
---@type table[]
M.templates = {}
for _, sub in ipairs({ "get", "upgrade", "tree" }) do
    local s = SUBS[sub]
    M.templates[#M.templates + 1] = {
        name = s.label,
        desc = s.desc,
        group = "Dependencies",
        builder = function(ctx)
            local root = (ctx and ctx.root) or resolve_root()
            if vim.fn.filereadable(vim.fs.joinpath(root, "rebar.config")) ~= 1 then
                return nil
            end
            local rebar3 = toolchain.resolve("erlang", "rebar3", root) or "rebar3"
            local cmd = { rebar3 }
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

--- The `:LvimLang deps <get|upgrade|tree> [args…]` command: `rebar3 <sub>` through lvim-tasks.
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
    run_rebar3(root, argv, s.label)
end

return M
