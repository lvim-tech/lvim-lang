-- lvim-lang.providers.dart.pub: `flutter pub` dependency commands, run through lvim-tasks.
-- Both the :LvimLang pub <sub> command and the registered lvim-tasks templates build from ONE
-- spec builder, so the run shows up in the lvim-tasks panel / history / dock with the correct
-- flutter binary (resolved per project through core.toolchain) and cwd (the pubspec root).
--
---@module "lvim-lang.providers.dart.pub"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

-- The supported `pub` subcommands (argv after `flutter`).
---@type table<string, { args: string[], label: string, desc: string }>
local SUBS = {
    get = { args = { "pub", "get" }, label = "flutter pub get", desc = "Fetch package dependencies" },
    upgrade = { args = { "pub", "upgrade" }, label = "flutter pub upgrade", desc = "Upgrade package dependencies" },
}

local M = {}

--- Resolve the pubspec project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "pubspec.yaml", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Build the lvim-tasks spec for a `pub` subcommand at `root` (nil for an unknown sub).
---@param sub string
---@param root string
---@param extra? string[]  extra argv appended after the subcommand
---@return table|nil
local function build(sub, root, extra)
    local s = SUBS[sub]
    if not s then
        return nil
    end
    local flutter = toolchain.resolve("dart", "flutter", root) or "flutter"
    local cmd = { flutter }
    vim.list_extend(cmd, s.args)
    if extra then
        vim.list_extend(cmd, extra)
    end
    return { name = s.label, cmd = cmd, cwd = root, group = "Dependencies" }
end

-- lvim-tasks templates (registered via the provider's `tasks` field): each applies only in a
-- Flutter project (pubspec.yaml present at the resolved root).
---@type table[]
M.templates = {}
for sub, s in pairs(SUBS) do
    M.templates[#M.templates + 1] = {
        name = s.label,
        desc = s.desc,
        group = "Dependencies",
        builder = function(ctx)
            local root = (ctx and ctx.root) or resolve_root()
            if vim.fn.filereadable(root .. "/pubspec.yaml") ~= 1 then
                return nil
            end
            return build(sub, root)
        end,
    }
end

--- The `:LvimLang pub <get|upgrade> [args…]` command: build and run through lvim-tasks.
---@param args string[]
---@param ctx table  { provider, root, bufnr }
---@return nil
function M.command(args, ctx)
    local sub = args[1] or "get"
    if not SUBS[sub] then
        vim.notify("lvim-lang: usage — :LvimLang pub <get|upgrade>", vim.log.levels.INFO, TITLE)
        return
    end
    local root = ctx.root or resolve_root()
    local spec = build(sub, root, { unpack(args, 2) })
    if spec then
        runner.run("dart", spec)
    end
end

return M
