-- lvim-lang.providers.zig.deps: Zig package (build.zig.zon) commands, run through lvim-tasks.
-- Zig's dependency manifest is `build.zig.zon`; `zig fetch --save <url|path>` copies a package into
-- the global cache and writes its name + hash into build.zig.zon, and `zig build --fetch` prefetches
-- every already-declared dependency without building. Both run through core.runner → lvim-tasks
-- (Dependencies group) with the correct `zig` binary (resolved per project through core.toolchain)
-- and cwd (the package root). core.runner runs `:checktime` on exit, so an edited build.zig.zon
-- reloads in open buffers.
--
---@module "lvim-lang.providers.zig.deps"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

-- The `:LvimLang deps <sub>` subcommands (argv after `zig`). All arg-less → also lvim-tasks templates.
---@type table<string, { args: string[], label: string, desc: string }>
local SUBS = {
    fetch = { args = { "build", "--fetch" }, label = "zig build --fetch", desc = "Prefetch all declared dependencies" },
}

local M = {}

--- Resolve the Zig package root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "build.zig", "build.zig.zon", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `zig <argv…>` for a root through lvim-tasks (Dependencies group, `gcc` matcher).
---@param root string
---@param argv string[]
---@param name string
---@return nil
local function run_zig(root, argv, name)
    local zig = toolchain.resolve("zig", "zig", root) or "zig"
    local cmd = { zig }
    vim.list_extend(cmd, argv)
    runner.run("zig", { name = name, cmd = cmd, cwd = root, group = "Dependencies", matcher = "gcc" })
end

-- lvim-tasks templates (via the provider's `tasks` field): the arg-less subcommands, each applying
-- only in a Zig package (build.zig.zon at the resolved root).
---@type table[]
M.templates = {}
for _, s in pairs(SUBS) do
    M.templates[#M.templates + 1] = {
        name = s.label,
        desc = s.desc,
        group = "Dependencies",
        builder = function(ctx)
            local root = (ctx and ctx.root) or resolve_root()
            if vim.fn.filereadable(root .. "/build.zig.zon") ~= 1 then
                return nil
            end
            local zig = toolchain.resolve("zig", "zig", root) or "zig"
            local cmd = { zig }
            vim.list_extend(cmd, s.args)
            return { name = s.label, cmd = cmd, cwd = root, group = "Dependencies", matcher = "gcc" }
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

--- The `:LvimLang deps <sub> [args…]` command: the arg-less package commands through lvim-tasks.
---@param args string[]
---@param ctx table
---@return nil
function M.command(args, ctx)
    local sub = args[1] or "fetch"
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
    run_zig(root, argv, s.label)
end

--- The `:LvimLang fetch <url|path>` command: `zig fetch --save <url|path>` — copy the package into
--- the cache and record its name + hash in build.zig.zon.
---@param args string[]
---@param ctx table
---@return nil
function M.fetch(args, ctx)
    if #args == 0 then
        vim.notify("lvim-lang: usage — :LvimLang fetch <url|path> [--save=name]", vim.log.levels.INFO, TITLE)
        return
    end
    -- Insert `--save` right after `fetch` unless the user already passed a `--save…` flag.
    local argv = { "fetch" }
    local has_save = false
    for _, a in ipairs(args) do
        if a == "--save" or a:match("^%-%-save") then
            has_save = true
            break
        end
    end
    if not has_save then
        argv[#argv + 1] = "--save"
    end
    vim.list_extend(argv, args)
    run_zig(ctx.root or resolve_root(), argv, "zig fetch " .. args[#args])
end

return M
