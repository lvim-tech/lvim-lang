-- lvim-lang.providers.typescript.dap: JS/TS debugging through lvim-dap, backed by js-debug.
-- The static adapter + base launch configurations are handed to lvim-ls via the vtsls server config's
-- `dap` field (auto-registered with lvim-dap on attach). js-debug runs as a `server` adapter
-- (`js-debug-adapter ${port}`, type `pwa-node`). The node runtime is resolved per session through the
-- toolchain; TypeScript is launched through a project-local `tsx` loader when present. `:LvimLang
-- debug` continues / starts a session; `:LvimLang debug-test` runs the test under the cursor under the
-- debugger.
--
---@module "lvim-lang.providers.typescript.dap"

local toolchain = require("lvim-lang.core.toolchain")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The JS/TS project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "package.json", "tsconfig.json", "jsconfig.json", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The node binary for a root (else `node`).
---@param root string
---@return string
local function node_bin(root)
    return toolchain.resolve("typescript", "node", root) or "node"
end

--- The js-debug adapter binary: an explicit config path → the mason bin → PATH.
---@return string
local function js_debug_bin()
    local o = require("lvim-lang.config").providers.typescript or {}
    if o.js_debug_path and vim.fn.executable(o.js_debug_path) == 1 then
        return o.js_debug_path
    end
    local ok, pkg = pcall(require, "lvim-pkg")
    if ok and type(pkg.bin_dir) == "function" then
        local p = vim.fs.joinpath(pkg.bin_dir(), "js-debug-adapter")
        if vim.fn.executable(p) == 1 then
            return p
        end
    end
    local p = vim.fn.exepath("js-debug-adapter")
    return p ~= "" and p or "js-debug-adapter"
end

--- A project-local `tsx` runtime for `root`, if present (to launch TypeScript directly), else nil.
---@param root string
---@return string|nil
local function tsx_runtime(root)
    local p = vim.fs.joinpath(vim.fs.root(root, { "package.json" }) or root, "node_modules", ".bin", "tsx")
    return vim.fn.executable(p) == 1 and p or nil
end

--- The js-debug server adapter: `js-debug-adapter ${port}` (lvim-dap resolves a free port).
---@return fun(callback: fun(adapter: table), config: table)
local function adapter()
    return function(callback, _config)
        callback({
            type = "server",
            host = "localhost",
            port = "${port}",
            executable = { command = js_debug_bin(), args = { "${port}" } },
        })
    end
end

--- The static `dap` field for the vtsls server config (adapter + base configurations for every JS/TS
--- filetype). `pwa-node` is registered under each of the four filetypes.
---@return table
function M.spec()
    local function base_configs()
        local root = root_of(vim.api.nvim_get_current_buf())
        local node = node_bin(root)
        local tsx = tsx_runtime(root)
        return {
            {
                type = "pwa-node",
                request = "launch",
                name = "Launch file",
                program = "${file}",
                cwd = "${workspaceFolder}",
                runtimeExecutable = tsx or node, -- tsx runs TypeScript directly when available
                sourceMaps = true,
                skipFiles = { "<node_internals>/**" },
            },
            {
                type = "pwa-node",
                request = "launch",
                name = "Launch npm script",
                runtimeExecutable = require("lvim-lang.providers.typescript.pm").detect(root),
                runtimeArgs = function()
                    return { "run", vim.fn.input("Script: ", "dev") }
                end,
                cwd = "${workspaceFolder}",
                sourceMaps = true,
                skipFiles = { "<node_internals>/**" },
            },
            {
                type = "pwa-node",
                request = "attach",
                name = "Attach (localhost:9229)",
                port = 9229,
                cwd = "${workspaceFolder}",
                skipFiles = { "<node_internals>/**" },
            },
        }
    end
    local adapters = { ["pwa-node"] = adapter() }
    local configurations = {}
    for _, ft in ipairs({ "typescript", "typescriptreact", "javascript", "javascriptreact" }) do
        configurations[ft] = base_configs()
    end
    return { adapters = adapters, configurations = configurations }
end

--- The title of the enclosing `it` / `test` / `describe` under the cursor (treesitter), or nil.
---@param bufnr integer
---@return string|nil
local function enclosing_title(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil
    end
    while node do
        if node:type() == "call_expression" then
            local fn = node:field("function")[1]
            local base = (fn and vim.treesitter.get_node_text(fn, bufnr) or ""):match("^([%a]+)") or ""
            if base == "it" or base == "test" or base == "describe" then
                local args = node:field("arguments")[1]
                if args then
                    for child in args:iter_children() do
                        if child:type() == "string" then
                            return (vim.treesitter.get_node_text(child, bufnr):gsub("^['\"`]", ""):gsub("['\"`]$", ""))
                        end
                    end
                end
            end
        end
        node = node:parent()
    end
    return nil
end

--- `:LvimLang debug` — continue / start a debug session (lvim-dap picks a configuration).
---@param _args string[]
---@param _ctx table
---@return nil
function M.debug(_args, _ctx)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok then
        vim.notify("lvim-lang: lvim-dap not available", vim.log.levels.WARN, TITLE)
        return
    end
    dap.continue()
end

--- `:LvimLang debug-test` — debug the test under the cursor: launch the project-local test runner
--- (vitest / jest) under js-debug, filtered to the enclosing title.
---@param _args string[]
---@param ctx table
---@return nil
function M.debug_test(_args, ctx)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok then
        vim.notify("lvim-lang: lvim-dap not available", vim.log.levels.WARN, TITLE)
        return
    end
    local title = enclosing_title(ctx.bufnr)
    if not title then
        vim.notify("lvim-lang: cursor is not inside an it()/test()/describe() block", vim.log.levels.WARN, TITLE)
        return
    end
    local root = ctx.root or root_of(ctx.bufnr)
    local file = vim.api.nvim_buf_get_name(ctx.bufnr)
    -- vitest: `vitest run <file> -t <title>`; jest: `jest <file> -t <title>` (both under node).
    local vitest = vim.fs.joinpath(vim.fs.root(root, { "package.json" }) or root, "node_modules", ".bin", "vitest")
    local jest = vim.fs.joinpath(vim.fs.root(root, { "package.json" }) or root, "node_modules", ".bin", "jest")
    local program, args
    if vim.fn.executable(vitest) == 1 then
        program, args = vitest, { "run", file, "-t", title }
    elseif vim.fn.executable(jest) == 1 then
        program, args = jest, { file, "-t", title }
    else
        vim.notify("lvim-lang: no project-local vitest / jest to debug", vim.log.levels.WARN, TITLE)
        return
    end
    dap.run({
        type = "pwa-node",
        request = "launch",
        name = "Debug test " .. title,
        program = program,
        args = args,
        cwd = root,
        runtimeExecutable = node_bin(root),
        sourceMaps = true,
        skipFiles = { "<node_internals>/**" },
        console = "integratedTerminal",
    })
end

return M
