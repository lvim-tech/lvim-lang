-- lvim-lang.providers.typescript.codegen: TypeScript code generation — declaration files via tsc.
-- `tsc --declaration --emitDeclarationOnly` emits `.d.ts` type declarations for the project (per its
-- tsconfig), through lvim-tasks so the run is visible and `:checktime` picks up the emitted files.
-- tsc is resolved per root through the toolchain (a project-local install wins), so no extra install
-- is needed when the project already depends on typescript.
--
---@module "lvim-lang.providers.typescript.codegen"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The JS/TS project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "tsconfig.json", "package.json", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- `:LvimLang types [args]` — emit `.d.ts` declarations (`tsc --declaration --emitDeclarationOnly`).
---@param args string[]
---@param ctx table
---@return nil
function M.types(args, ctx)
    local root = ctx.root or root_of(ctx.bufnr)
    local tsc = toolchain.resolve("typescript", "tsc", root)
    if not tsc then
        vim.notify(
            "lvim-lang: tsc not found — add `typescript` to the project (or install it via the installer)",
            vim.log.levels.WARN,
            TITLE
        )
        return
    end
    local cmd = { tsc, "--declaration", "--emitDeclarationOnly" }
    vim.list_extend(cmd, args)
    runner.run("typescript", {
        name = "tsc --declaration",
        cmd = cmd,
        cwd = root,
        group = "Build",
        matcher = "typescript",
    })
end

return M
