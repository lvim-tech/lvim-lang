-- lvim-lang.core.ensure: make a mason tool available ON DEMAND.
-- Some tools are not part of a filetype's install union (they are used ad-hoc, e.g. the Go codegen
-- tools) — so instead of offering them upfront, a command that needs one calls ensure.tool: if the
-- binary is already on PATH it runs immediately; otherwise the tool is installed through lvim-pkg
-- (the same mason-registry PURL handlers as the installer — NO mason.nvim) and the callback fires on
-- success. This keeps the "only tools you actually use get installed" contract for on-demand tools.
--
---@module "lvim-lang.core.ensure"

local TITLE = { title = "lvim-lang" }

local M = {}

--- Ensure `mason` (binary `bin`, default = mason name) is available, then call `cb(binpath)`.
--- Already on PATH → immediate. Missing → install via lvim-pkg, then resolve and call cb. When
--- lvim-pkg is unavailable the user is pointed at the installer.
---@param mason string           mason-registry package name
---@param bin? string            binary name if it differs from the package
---@param cb fun(binpath: string) run with the resolved binary
---@return nil
function M.tool(mason, bin, cb)
    bin = bin or mason
    local p = vim.fn.exepath(bin)
    if p ~= "" then
        return cb(p)
    end
    local ok, pkg = pcall(require, "lvim-pkg")
    if not ok or type(pkg.install) ~= "function" then
        vim.notify(
            ("lvim-lang: %s not found — install it via :LvimInstaller"):format(mason),
            vim.log.levels.WARN,
            TITLE
        )
        return
    end
    vim.notify(("lvim-lang: installing %s…"):format(mason), vim.log.levels.INFO, TITLE)
    pkg.install("mason", { mason }, function()
        vim.schedule(function()
            local p2 = vim.fn.exepath(bin)
            if p2 ~= "" then
                cb(p2)
            else
                vim.notify(
                    ("lvim-lang: %s install did not produce a binary on PATH"):format(mason),
                    vim.log.levels.ERROR,
                    TITLE
                )
            end
        end)
    end)
end

return M
