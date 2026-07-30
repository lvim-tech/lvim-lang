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

--- Ensure a LuaRocks rock is available, then call `cb(binpath)`.
---
--- Not every rock is in the mason registry — `busted`, the Lua test runner, is not — and asking the
--- registry for one that is absent installs nothing and reports only that no binary appeared. This
--- goes to lvim-pkg's rock installer instead, which puts it in the managed tree like any package.
---@param rock string           luarocks rock name
---@param bin? string           binary name if it differs from the rock
---@param cb fun(binpath: string) run with the resolved binary
---@return nil
function M.rock(rock, bin, cb)
    bin = bin or rock
    local p = vim.fn.exepath(bin)
    if p ~= "" then
        return cb(p)
    end
    local ok, pkg = pcall(require, "lvim-pkg")
    if not ok or type(pkg.install_rock) ~= "function" then
        vim.notify(
            ("lvim-lang: %s not found — install it with `luarocks install %s`"):format(bin, rock),
            vim.log.levels.WARN,
            TITLE
        )
        return
    end
    vim.notify(("lvim-lang: installing %s…"):format(rock), vim.log.levels.INFO, TITLE)
    pkg.install_rock({ name = rock, bins = { bin } }, function(err)
        vim.schedule(function()
            local p2 = vim.fn.exepath(bin)
            if p2 ~= "" then
                cb(p2)
            else
                vim.notify(
                    ("lvim-lang: %s install failed%s"):format(rock, err and (" — " .. err) or ""),
                    vim.log.levels.ERROR,
                    TITLE
                )
            end
        end)
    end)
end

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
