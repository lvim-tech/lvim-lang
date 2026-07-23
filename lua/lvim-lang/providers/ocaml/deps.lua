-- lvim-lang.providers.ocaml.deps: dependency operations through opam.
-- An OCaml project DECLARES its dependencies in `dune-project` (the `(depends …)` of a
-- `(package …)` stanza) and/or a generated `<name>.opam` file — so ADDING / REMOVING a dependency
-- means editing those files by hand; there is no clean, non-destructive CLI verb that rewrites them
-- (inventing one would be a kludge). This module therefore exposes the SAFE, read-or-resolve
-- operations opam does own: `install` (install the project's declared deps into the switch),
-- `list` (the installed packages) and `upgrade` (upgrade the switch). Runs land in the lvim-tasks
-- panel (Dependencies group); core.runner runs `:checktime` on exit so an edited lock/metadata
-- reloads in open buffers.
--
---@module "lvim-lang.providers.ocaml.deps"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

-- The `:LvimLang deps <sub>` subcommands (argv after `opam`). All arg-less → also lvim-tasks templates.
---@type table<string, { args: string[], label: string, desc: string }>
local SUBS = {
    install = {
        args = { "install", ".", "--deps-only", "--yes" },
        label = "opam install --deps-only",
        desc = "Install the project's declared dependencies into the active switch",
    },
    list = { args = { "list" }, label = "opam list", desc = "List the packages installed in the switch" },
    upgrade = { args = { "upgrade", "--yes" }, label = "opam upgrade", desc = "Upgrade the switch's packages" },
}

local M = {}

--- Resolve the dune project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "dune-project", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `opam <argv…>` for a root through lvim-tasks (Dependencies group, generic matcher).
---@param root string
---@param argv string[]
---@param name string
---@return nil
local function run_opam(root, argv, name)
    local opam = toolchain.resolve("ocaml", "opam", root) or "opam"
    local cmd = { opam }
    vim.list_extend(cmd, argv)
    runner.run("ocaml", { name = name, cmd = cmd, cwd = root, group = "Dependencies", matcher = "generic" })
end

-- lvim-tasks templates (via the provider's `tasks` field): the arg-less subcommands, each applying
-- only in a dune project (dune-project at the resolved root).
---@type table[]
M.templates = {}
for sub, s in pairs(SUBS) do
    M.templates[#M.templates + 1] = {
        name = s.label,
        desc = s.desc,
        group = "Dependencies",
        builder = function(ctx)
            local root = (ctx and ctx.root) or resolve_root()
            if vim.fn.filereadable(root .. "/dune-project") ~= 1 then
                return nil
            end
            local opam = toolchain.resolve("ocaml", "opam", root) or "opam"
            local cmd = { opam }
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

--- The `:LvimLang deps <sub> [args…]` command: `opam <install|list|upgrade>` through lvim-tasks. Add
--- / remove a dependency by editing the `(depends …)` stanza in dune-project / the `*.opam` file.
---@param args string[]
---@param ctx table
---@return nil
function M.command(args, ctx)
    local sub = args[1] or "list"
    local s = SUBS[sub]
    if not s then
        vim.notify(
            "lvim-lang: usage — :LvimLang deps <"
                .. table.concat(M.subs(), "|")
                .. ">  (add / remove a dependency by editing dune-project / *.opam `depends`)",
            vim.log.levels.INFO,
            TITLE
        )
        return
    end
    local root = ctx.root or resolve_root()
    local argv = vim.list_extend(vim.deepcopy(s.args), { unpack(args, 2) })
    run_opam(root, argv, s.label)
end

return M
