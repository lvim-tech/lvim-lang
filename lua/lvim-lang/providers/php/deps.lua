-- lvim-lang.providers.php.deps: Composer dependency commands, run through lvim-tasks.
-- install / update / require / remove / dump-autoload all build from ONE spec runner, so runs land in
-- the lvim-tasks panel / history / dock with the correct `composer` binary (resolved per project
-- through core.toolchain) and cwd (the composer.json root). core.runner runs `:checktime` on exit, so
-- an edited `composer.json` / `composer.lock` reloads in open buffers. The arg-less subcommands
-- (install / update / dump-autoload) also register as lvim-tasks templates.
--
---@module "lvim-lang.providers.php.deps"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

-- The `:LvimLang deps <sub>` subcommands (argv after `composer`). Arg-less → also lvim-tasks
-- templates. `require` / `remove` take a package argument, so they are their OWN commands (below).
---@type table<string, { args: string[], label: string, desc: string }>
local SUBS = {
    install = { args = { "install" }, label = "composer install", desc = "Install Composer dependencies" },
    update = { args = { "update" }, label = "composer update", desc = "Update Composer dependencies" },
    ["dump-autoload"] = {
        args = { "dump-autoload" },
        label = "composer dump-autoload",
        desc = "Regenerate the Composer autoloader",
    },
}

local M = {}

--- Resolve the PHP project root for the current buffer (nearest `composer.json`, else `.git`, else
--- the file's directory, else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "composer.json", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `composer <argv…>` for a root through lvim-tasks (`group`, `generic` matcher).
---@param root string
---@param argv string[]
---@param name string
---@param group string
---@return nil
local function run_composer(root, argv, name, group)
    local composer = toolchain.resolve("php", "composer", root) or "composer"
    local cmd = { composer }
    vim.list_extend(cmd, argv)
    runner.run("php", { name = name, cmd = cmd, cwd = root, group = group, matcher = "generic" })
end

-- lvim-tasks templates (via the provider's `tasks` field): the arg-less subcommands, each applying
-- only in a Composer project (a `composer.json` at or above the resolved root).
---@type table[]
M.templates = {}
for _, s in pairs(SUBS) do
    M.templates[#M.templates + 1] = {
        name = s.label,
        desc = s.desc,
        group = "Dependencies",
        builder = function(ctx)
            local root = (ctx and ctx.root) or resolve_root()
            local buf = vim.api.nvim_get_current_buf()
            if vim.api.nvim_buf_get_name(buf) ~= "" and not vim.fs.root(buf, { "composer.json" }) then
                return nil
            end
            local composer = toolchain.resolve("php", "composer", root) or "composer"
            local cmd = { composer }
            vim.list_extend(cmd, s.args)
            return { name = s.label, cmd = cmd, cwd = root, group = "Dependencies", matcher = "generic" }
        end,
    }
end

--- The `deps` subcommand names (for command completion), sorted.
---@return string[]
function M.subs()
    local names = vim.tbl_keys(SUBS)
    table.sort(names)
    return names
end

--- `:LvimLang deps <install|update|dump-autoload> [args…]`.
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
    run_composer(root, argv, s.label, "Dependencies")
end

--- `:LvimLang require <package[:constraint]> [args]` — `composer require`. A trailing `@dev` /
--- `:^1.0` version constraint is passed through as Composer expects (`vendor/pkg:^1.0`).
---@param args string[]
---@param ctx table
---@return nil
function M.require(args, ctx)
    if #args == 0 then
        vim.notify("lvim-lang: usage — :LvimLang require <package[:constraint]> [args]", vim.log.levels.INFO, TITLE)
        return
    end
    local argv = { "require" }
    vim.list_extend(argv, args)
    run_composer(ctx.root or resolve_root(), argv, "composer require " .. args[1], "Dependencies")
end

--- `:LvimLang remove <package>` — `composer remove`.
---@param args string[]
---@param ctx table
---@return nil
function M.remove(args, ctx)
    if #args == 0 then
        vim.notify("lvim-lang: usage — :LvimLang remove <package>", vim.log.levels.INFO, TITLE)
        return
    end
    local argv = { "remove" }
    vim.list_extend(argv, args)
    run_composer(ctx.root or resolve_root(), argv, "composer remove " .. args[1], "Dependencies")
end

return M
