-- lvim-lang.providers.python.codegen: Python code generation — type stubs via basedpyright.
-- `basedpyright --createstub <import>` writes `.pyi` type stubs for a package into the project's
-- `typings/` directory (which basedpyright then reads for better inference on untyped libraries).
-- The CLI ships with the basedpyright LSP package, resolved per root through the venv-aware
-- toolchain, so no extra install is needed. Runs off the UI thread (vim.system); `:checktime` picks
-- up the written files.
--
---@module "lvim-lang.providers.python.codegen"

local toolchain = require("lvim-lang.core.toolchain")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The Python project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "pyproject.toml", "setup.py", "requirements.txt", "Pipfile", ".git" })
            or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- `:LvimLang stub <import>` — generate `.pyi` type stubs for an importable package
--- (`basedpyright --createstub <import>`), written under the project's `typings/`.
---@param args string[]
---@param ctx table
---@return nil
function M.stub(args, ctx)
    if #args == 0 then
        vim.notify("lvim-lang: usage — :LvimLang stub <import>  (e.g. requests)", vim.log.levels.INFO, TITLE)
        return
    end
    local root = ctx.root or root_of(ctx.bufnr)
    local cli = toolchain.resolve("python", "basedpyright-cli", root)
    if not cli then
        vim.notify(
            "lvim-lang: basedpyright CLI not found — install basedpyright via the installer",
            vim.log.levels.WARN,
            TITLE
        )
        return
    end
    local import = args[1]
    vim.notify("lvim-lang: creating type stubs for " .. import .. "…", vim.log.levels.INFO, TITLE)
    vim.system({ cli, "--createstub", import }, { cwd = root, text = true }, function(res)
        vim.schedule(function()
            if res.code ~= 0 then
                vim.notify(
                    "lvim-lang: basedpyright --createstub failed: " .. (res.stderr or res.stdout or ""),
                    vim.log.levels.ERROR,
                    TITLE
                )
                return
            end
            vim.notify(("lvim-lang: stubs for %s written under typings/"):format(import), vim.log.levels.INFO, TITLE)
            pcall(vim.cmd, "checktime")
        end)
    end)
end

return M
