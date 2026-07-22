-- lvim-lang.providers.go.dap: Go debugging through lvim-dap, backed by Delve (`dlv dap`).
-- The static adapter + base launch/test configurations are handed to lvim-ls via the gopls server
-- config's `dap` field (auto-registered with lvim-dap on attach). The `dlv` binary is resolved per
-- project root through core.toolchain at launch time (a version-managed toolchain and the PATH one
-- both work). `:LvimLang debug` continues/starts a session; `:LvimLang debug-test` debugs exactly
-- the test under the cursor (treesitter-found), passing `-test.run ^Name$`.
--
---@module "lvim-lang.providers.go.dap"

local toolchain = require("lvim-lang.core.toolchain")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The Go module/workspace root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "go.work", "go.mod", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The Delve DAP adapter: a factory that resolves `dlv` per root and runs `dlv dap`.
---@return fun(callback: fun(adapter: table), config: table)
local function adapter()
    return function(callback, config)
        local root = (config and config.cwd) or vim.uv.cwd() or "."
        local dlv = toolchain.resolve("go", "dlv", root) or "dlv"
        callback({ type = "executable", command = dlv, args = { "dap" } })
    end
end

--- The static `dap` field for the gopls server config (adapter + base configurations).
---@return table
function M.spec()
    return {
        adapters = { go = adapter() },
        configurations = {
            go = {
                {
                    type = "go",
                    request = "launch",
                    name = "Debug package",
                    mode = "debug",
                    program = "${workspaceFolder}",
                },
                { type = "go", request = "launch", name = "Debug file", mode = "debug", program = "${file}" },
                {
                    type = "go",
                    request = "launch",
                    name = "Debug test (package)",
                    mode = "test",
                    program = "${workspaceFolder}",
                },
                { type = "go", request = "attach", name = "Attach (local)", mode = "local" },
            },
        },
    }
end

--- The name of the Test/Benchmark/Fuzz function enclosing the cursor (treesitter), or nil.
---@param bufnr integer
---@return string|nil
local function enclosing_test(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil
    end
    while node do
        if node:type() == "function_declaration" then
            local name_node = node:field("name")[1]
            if name_node then
                local name = vim.treesitter.get_node_text(name_node, bufnr)
                if name:match("^Test") or name:match("^Benchmark") or name:match("^Fuzz") then
                    return name
                end
            end
            return nil
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

--- `:LvimLang debug-test` — debug exactly the test under the cursor (`dlv` in test mode with
--- `-test.run ^Name$`), in the file's package directory.
---@param _args string[]
---@param ctx table
---@return nil
function M.debug_test(_args, ctx)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok then
        vim.notify("lvim-lang: lvim-dap not available", vim.log.levels.WARN, TITLE)
        return
    end
    local name = enclosing_test(ctx.bufnr)
    if not name then
        vim.notify("lvim-lang: cursor is not inside a Test/Benchmark/Fuzz function", vim.log.levels.WARN, TITLE)
        return
    end
    local buf = vim.api.nvim_buf_get_name(ctx.bufnr)
    local dir = buf ~= "" and vim.fs.dirname(buf) or root_of(ctx.bufnr)
    dap.run({
        type = "go",
        request = "launch",
        name = "Debug test " .. name,
        mode = "test",
        program = dir,
        args = { "-test.run", "^" .. name .. "$" },
    })
end

return M
