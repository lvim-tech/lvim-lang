-- lvim-lang.providers.go.mod: Go module commands (`go mod …` + `go get`), run through lvim-tasks.
-- Both :LvimLang mod <sub> / :LvimLang get and the registered lvim-tasks templates build from ONE
-- spec builder, so runs land in the lvim-tasks panel / history / dock with the correct `go` binary
-- (resolved per project through core.toolchain) and cwd (the module root). core.runner runs
-- `:checktime` on exit, so an edited go.mod / go.sum / vendored tree reloads in open buffers.
--
---@module "lvim-lang.providers.go.mod"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

-- The supported `go mod` subcommands (argv after `go`). `templated = true` ones (arg-less) also
-- register as lvim-tasks templates; `why` needs a module path on the command line.
---@type table<string, { args: string[], label: string, desc: string, templated?: boolean }>
local SUBS = {
    tidy = {
        args = { "mod", "tidy" },
        label = "go mod tidy",
        desc = "Add missing / remove unused modules",
        templated = true,
    },
    download = {
        args = { "mod", "download" },
        label = "go mod download",
        desc = "Download modules to the cache",
        templated = true,
    },
    verify = {
        args = { "mod", "verify" },
        label = "go mod verify",
        desc = "Verify dependencies have expected content",
        templated = true,
    },
    graph = {
        args = { "mod", "graph" },
        label = "go mod graph",
        desc = "Print the module requirement graph",
        templated = true,
    },
    why = { args = { "mod", "why" }, label = "go mod why", desc = "Explain why a module is needed" },
}

local M = {}

--- Resolve the Go module/workspace root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "go.work", "go.mod", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Build the lvim-tasks spec for a `go mod` subcommand at `root` (nil for an unknown sub).
---@param sub string
---@param root string
---@param extra? string[]  extra argv appended after the subcommand
---@return table|nil
local function build(sub, root, extra)
    local s = SUBS[sub]
    if not s then
        return nil
    end
    local go = toolchain.resolve("go", "go", root) or "go"
    local cmd = { go }
    vim.list_extend(cmd, s.args)
    if extra then
        vim.list_extend(cmd, extra)
    end
    return { name = s.label, cmd = cmd, cwd = root, group = "Dependencies", matcher = "go" }
end

-- lvim-tasks templates (via the provider's `tasks` field): only the arg-less subcommands, each
-- applying only in a Go module (go.mod present at the resolved root).
---@type table[]
M.templates = {}
for sub, s in pairs(SUBS) do
    if s.templated then
        M.templates[#M.templates + 1] = {
            name = s.label,
            desc = s.desc,
            group = "Dependencies",
            builder = function(ctx)
                local root = (ctx and ctx.root) or resolve_root()
                if vim.fn.filereadable(root .. "/go.mod") ~= 1 then
                    return nil
                end
                return build(sub, root)
            end,
        }
    end
end

--- The `mod` subcommand names (for command completion).
---@return string[]
function M.subs()
    local names = vim.tbl_keys(SUBS)
    table.sort(names)
    return names
end

--- The `:LvimLang mod <sub> [args…]` command: build and run `go mod <sub>` through lvim-tasks.
---@param args string[]
---@param ctx table  { provider, root, bufnr }
---@return nil
function M.command(args, ctx)
    local sub = args[1] or "tidy"
    if not SUBS[sub] then
        vim.notify(
            "lvim-lang: usage — :LvimLang mod <" .. table.concat(M.subs(), "|") .. ">",
            vim.log.levels.INFO,
            TITLE
        )
        return
    end
    local root = ctx.root or resolve_root()
    local spec = build(sub, root, { unpack(args, 2) })
    if spec then
        runner.run("go", spec)
    end
end

--- The `:LvimLang get <module…>` command: `go get <args>` (add / upgrade a dependency; `-u ./...`
--- to upgrade all). Needs at least one argument.
---@param args string[]
---@param ctx table  { provider, root, bufnr }
---@return nil
function M.get(args, ctx)
    if #args == 0 then
        vim.notify("lvim-lang: usage — :LvimLang get <module[@version]> | -u ./...", vim.log.levels.INFO, TITLE)
        return
    end
    local root = ctx.root or resolve_root()
    local go = toolchain.resolve("go", "go", root) or "go"
    local cmd = { go, "get" }
    vim.list_extend(cmd, args)
    runner.run(
        "go",
        { name = "go get " .. table.concat(args, " "), cmd = cmd, cwd = root, group = "Dependencies", matcher = "go" }
    )
end

return M
