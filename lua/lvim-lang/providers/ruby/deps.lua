-- lvim-lang.providers.ruby.deps: Bundler dependency commands, run through lvim-tasks.
-- install / update / outdated / add / remove build from ONE spec table, so runs land in the
-- lvim-tasks panel / history / dock with the correct `bundle` binary (resolved per project through
-- core.toolchain) and cwd (the project root). core.runner runs `:checktime` on exit, so an edited
-- Gemfile / Gemfile.lock reloads in open buffers. Bundler edits the Gemfile itself for add / remove
-- (a clean, non-destructive CLI verb), unlike hand-editing — so those are exposed as commands too.
--
---@module "lvim-lang.providers.ruby.deps"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

-- The `:LvimLang deps <sub>` subcommands (argv tail after `bundle`). All arg-less → also lvim-tasks
-- templates.
---@type table<string, { args: string[], label: string, desc: string }>
local SUBS = {
    install = { args = { "install" }, label = "bundle install", desc = "Install the locked gems" },
    update = { args = { "update" }, label = "bundle update", desc = "Update gems (respecting the Gemfile)" },
    outdated = { args = { "outdated" }, label = "bundle outdated", desc = "List gems with newer versions" },
}

local M = {}

--- Resolve the Ruby project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "Gemfile", "Rakefile", ".ruby-version", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `bundle <argv…>` for a root through lvim-tasks (Dependencies group, `generic` matcher).
---@param root string
---@param argv string[]
---@param name string
---@return nil
local function run_bundle(root, argv, name)
    local bundle = toolchain.resolve("ruby", "bundle", root) or "bundle"
    local cmd = { bundle }
    vim.list_extend(cmd, argv)
    runner.run("ruby", { name = name, cmd = cmd, cwd = root, group = "Dependencies", matcher = "generic" })
end

-- lvim-tasks templates (via the provider's `tasks` field): the arg-less subcommands, each applying
-- only in a bundled project (Gemfile at the resolved root).
---@type table[]
M.templates = {}
for _, sub in ipairs({ "install", "update", "outdated" }) do
    local s = SUBS[sub]
    M.templates[#M.templates + 1] = {
        name = s.label,
        desc = s.desc,
        group = "Dependencies",
        builder = function(ctx)
            local root = (ctx and ctx.root) or resolve_root()
            if vim.fn.filereadable(vim.fs.joinpath(root, "Gemfile")) ~= 1 then
                return nil
            end
            local bundle = toolchain.resolve("ruby", "bundle", root) or "bundle"
            local cmd = { bundle }
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

--- The `:LvimLang deps <install|update|outdated> [args…]` command: `bundle <sub>` through lvim-tasks.
---@param args string[]
---@param ctx table
---@return nil
function M.command(args, ctx)
    local sub = args[1] or "install"
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
    run_bundle(root, argv, s.label)
end

--- The `:LvimLang add <gem[:version]> [args]` command: `bundle add`.
---@param args string[]
---@param ctx table
---@return nil
function M.add(args, ctx)
    if #args == 0 then
        vim.notify("lvim-lang: usage — :LvimLang add <gem> [--version …]", vim.log.levels.INFO, TITLE)
        return
    end
    run_bundle(ctx.root or resolve_root(), vim.list_extend({ "add" }, args), "bundle add " .. args[1])
end

--- The `:LvimLang remove <gem…>` command: `bundle remove`.
---@param args string[]
---@param ctx table
---@return nil
function M.remove(args, ctx)
    if #args == 0 then
        vim.notify("lvim-lang: usage — :LvimLang remove <gem…>", vim.log.levels.INFO, TITLE)
        return
    end
    run_bundle(ctx.root or resolve_root(), vim.list_extend({ "remove" }, args), "bundle remove " .. args[1])
end

--- The `:LvimLang update [gem…]` command: `bundle update` (all, or the named gems).
---@param args string[]
---@param ctx table
---@return nil
function M.update(args, ctx)
    run_bundle(ctx.root or resolve_root(), vim.list_extend({ "update" }, args), "bundle update")
end

return M
