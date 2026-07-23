-- lvim-lang.providers.elixir.dap: Elixir debugging through lvim-dap, backed by the elixir-ls debugger.
-- elixir-ls ships a STANDALONE debug adapter as a second binary inside its mason package
-- (`elixir-ls-debugger`, the `debug_adapter.sh` / `.bat` launcher) — an `executable` adapter that
-- speaks DAP over stdio, independent of the language server, so debugging works whichever LSP (elixir-ls
-- / lexical / next-ls) is chosen. The adapter's launch request is a `mix_task`: it starts the app and
-- runs a mix task (`run`, `test`, `phx.server`, …) under the debugger. Base configurations cover
-- running the app and the test suite. `:LvimLang debug` continues / starts a session; `:LvimLang
-- debug-test` debugs exactly the ExUnit test under the cursor (`mix test <file>:<line>` under the
-- adapter). The debugger binary is resolved through core.toolchain (config → mason → PATH), never
-- installed here.
--
---@module "lvim-lang.providers.elixir.dap"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")

local TITLE = { title = "lvim-lang" }

-- The default files the debug adapter must compile before an ExUnit `test` task can run.
---@type string[]
local TEST_REQUIRE_FILES = { "test/**/test_helper.exs", "test/**/*_test.exs" }

local M = {}

--- The Elixir provider's config block.
---@return table
local function opts()
    return config.providers.elixir or {}
end

--- The Elixir project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "mix.exs", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Resolve the elixir-ls debug adapter binary for `root`: the toolchain resolution (config → mason →
--- PATH), else the bare name (so the error surfaces at launch with a clear "install elixir-ls" hint).
---@param root string
---@return string
local function debugger_bin(root)
    return toolchain.resolve("elixir", "elixir-ls-debugger", root) or "elixir-ls-debugger"
end

--- The elixir-ls debugger `executable` adapter: the `debug_adapter.sh` launcher speaking DAP on stdio.
---@return fun(callback: fun(adapter: table), config: table)
local function adapter()
    return function(callback, dap_config)
        local root = (dap_config and dap_config.cwd) or vim.uv.cwd() or "."
        callback({ type = "executable", command = debugger_bin(root), args = {} })
    end
end

--- The static `dap` field for the Elixir server config (adapter + base configurations). The adapter is
--- registered under the `mix_task` type — the elixir-ls debugger's own request kind.
---@return table
function M.spec()
    return {
        adapters = { mix_task = adapter() },
        configurations = {
            elixir = {
                {
                    type = "mix_task",
                    name = "mix test",
                    request = "launch",
                    task = "test",
                    taskArgs = { "--trace" },
                    startApps = true,
                    projectDir = "${workspaceFolder}",
                    requireFiles = TEST_REQUIRE_FILES,
                },
                {
                    type = "mix_task",
                    name = "mix run",
                    request = "launch",
                    task = "run",
                    projectDir = "${workspaceFolder}",
                },
            },
        },
    }
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

--- `:LvimLang debug-test` — debug exactly the ExUnit test under the cursor. Runs
--- `mix test <file>:<line>` under the elixir-ls debugger (the test addressed by its block line).
---@param _args string[]
---@param ctx table
---@return nil
function M.debug_test(_args, ctx)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok then
        vim.notify("lvim-lang: lvim-dap not available", vim.log.levels.WARN, TITLE)
        return
    end
    local bufnr = ctx.bufnr
    local file = vim.api.nvim_buf_get_name(bufnr)
    if file == "" then
        vim.notify("lvim-lang: no file for this buffer", vim.log.levels.WARN, TITLE)
        return
    end
    local line = require("lvim-lang.providers.elixir.test").test_line(bufnr)
    local require_files = (opts().dap and opts().dap.test_require_files) or TEST_REQUIRE_FILES
    dap.run({
        type = "mix_task",
        request = "launch",
        name = "Debug test " .. vim.fs.basename(file) .. ":" .. line,
        task = "test",
        taskArgs = { file .. ":" .. line },
        startApps = true,
        projectDir = "${workspaceFolder}",
        requireFiles = require_files,
    })
end

return M
