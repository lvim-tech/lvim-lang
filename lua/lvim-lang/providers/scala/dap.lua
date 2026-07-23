-- lvim-lang.providers.scala.dap: Scala debugging through lvim-dap, driven BY metals.
-- Scala debugging is owned by the language server: metals starts a Debug Adapter (a DAP server over
-- its Bloop BSP connection) on demand when the client sends the `debug-adapter-start` executeCommand,
-- and returns the URI of that server. The DAP adapter here is therefore a `server` adapter whose
-- factory asks the attached metals client to start a debug session and connects to the returned
-- port — the canonical metals debug seam (the same shape as Java's jdtls
-- `vscode.java.startDebugSession`), NOT a hand-rolled BSP client.
--
-- metals resolves WHAT to run from a `runType` + the current file's `path` (it does not take a single
-- test method by name — Scala test frameworks are DSL-based): "runOrTestFile" runs or tests the file,
-- "testFile" tests the file's suites, "testTarget" tests the whole build target, "run" runs a main.
-- `:LvimLang debug` continues / starts a session (lvim-dap picks a configuration); `:LvimLang
-- debug-test` starts a "testFile" session for the current buffer.
--
---@module "lvim-lang.providers.scala.dap"

local config = require("lvim-lang.config")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The Scala provider's config block.
---@return table
local function opts()
    return config.providers.scala or {}
end

--- Parse the port from a metals debug-server URI ("127.0.0.1:PORT" / "tcp://127.0.0.1:PORT").
---@param uri string
---@return integer|nil
local function port_of(uri)
    return tonumber((uri:match(":(%d+)%s*$")))
end

--- The metals debug-session `server` adapter: asks the attached metals client to start a debug
--- session (`debug-adapter-start`, given a runType + the current file path) and connects to the
--- returned port. The configuration's `metals` field carries the runType (default "runOrTestFile");
--- the current buffer's URI is added as `path` when absent so metals resolves the target from it.
---@return fun(callback: fun(adapter: table), config: table)
local function adapter()
    return function(callback, run_config)
        local client = vim.lsp.get_clients({ name = "metals" })[1]
        if not client then
            vim.notify(
                "lvim-lang: metals is not attached — open a Scala file so the debug server can start",
                vim.log.levels.WARN,
                TITLE
            )
            return
        end
        local params = vim.deepcopy(run_config.metals or {})
        params.runType = params.runType or "runOrTestFile"
        if params.path == nil then
            params.path = vim.uri_from_bufnr(0)
        end
        client:request(
            "workspace/executeCommand",
            { command = "debug-adapter-start", arguments = { params } },
            function(err, res)
                if err or type(res) ~= "table" or type(res.uri) ~= "string" then
                    vim.notify(
                        "lvim-lang: metals could not start a debug session (is the build imported?)",
                        vim.log.levels.ERROR,
                        TITLE
                    )
                    return
                end
                local port = port_of(res.uri)
                if not port then
                    vim.notify(
                        "lvim-lang: metals returned an unparseable debug URI: " .. res.uri,
                        vim.log.levels.ERROR,
                        TITLE
                    )
                    return
                end
                callback({ type = "server", host = "127.0.0.1", port = port })
            end
        )
    end
end

--- The static `dap` field for the metals server config (adapter + base configurations). The
--- configurations are metals `runType`s — metals resolves the concrete target from the current file.
---@return table
function M.spec()
    return {
        adapters = { scala = adapter() },
        configurations = {
            scala = {
                {
                    type = "scala",
                    request = "launch",
                    name = "Run or test current file",
                    metals = { runType = "runOrTestFile" },
                },
                {
                    type = "scala",
                    request = "launch",
                    name = "Test current file",
                    metals = { runType = "testFile" },
                },
                {
                    type = "scala",
                    request = "launch",
                    name = "Test build target",
                    metals = { runType = "testTarget" },
                },
            },
        },
    }
end

--- `:LvimLang debug` — continue / start a debug session (lvim-dap picks a configuration; metals
--- resolves the target from the current file).
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

--- `:LvimLang debug-test` — start a metals "testFile" debug session for the current buffer (metals
--- resolves the suite(s) in the file). Scala has no clean per-test debug selector, so this debugs the
--- file's suites, not a single DSL test.
---@param _args string[]
---@param ctx table
---@return nil
function M.debug_test(_args, ctx)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok then
        vim.notify("lvim-lang: lvim-dap not available", vim.log.levels.WARN, TITLE)
        return
    end
    -- Metals starts the DAP server asynchronously; the short delay lets an in-flight import settle
    -- before the request, matching the other JVM providers' attach timing.
    local delay = opts().debug_attach_delay_ms or 500
    vim.defer_fn(function()
        dap.run({
            type = "scala",
            request = "launch",
            name = "Debug tests in " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(ctx.bufnr), ":t"),
            metals = { runType = "testFile", path = vim.uri_from_bufnr(ctx.bufnr) },
        })
    end, delay)
end

return M
