-- lvim-lang.providers.swift.dap: Swift debugging through lvim-dap, backed by lldb-dap (or CodeLLDB).
-- SwiftPM builds native binaries with debug info, so they are debugged with LLDB. The catalog default
-- is lldb-dap — the LLDB project's own DAP adapter (`lldb-dap`, an `executable` adapter), which ships
-- with recent Swift toolchains and mason; CodeLLDB (`codelldb --port ${port}`, a `server` adapter) is
-- offered as the alternative. The static adapter + base launch configurations are handed to lvim-ls
-- via the sourcekit-lsp server config's `dap` field (auto-registered with lvim-dap on attach).
-- `:LvimLang debug` continues/starts a session; `:LvimLang debug-test` builds the test bundle
-- (`swift build --build-tests`) and launches it under the debugger filtered to the test under the cursor.
--
---@module "lvim-lang.providers.swift.dap"

local toolchain = require("lvim-lang.core.toolchain")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The swift config block.
---@return table
local function opts()
    return require("lvim-lang.config").providers.swift or {}
end

--- The SwiftPM package root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "Package.swift", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Resolve the lldb-dap binary: an explicit config path → the toolchain (mason / beside swift / PATH).
---@param root string
---@return string
local function lldb_dap_bin(root)
    return toolchain.resolve("swift", "lldb-dap", root) or "lldb-dap"
end

--- Resolve the CodeLLDB binary: an explicit config path → PATH (the mason install).
---@return string
local function codelldb_bin()
    local o = opts()
    if o.codelldb_path and vim.fn.executable(o.codelldb_path) == 1 then
        return o.codelldb_path
    end
    local p = vim.fn.exepath("codelldb")
    return p ~= "" and p or "codelldb"
end

--- The CodeLLDB server adapter: `codelldb --port ${port}` (lvim-dap resolves a free port).
---@return fun(callback: fun(adapter: table), config: table)
local function codelldb_adapter()
    return function(callback, _config)
        callback({
            type = "server",
            port = "${port}",
            executable = { command = codelldb_bin(), args = { "--port", "${port}" } },
        })
    end
end

--- Prompt for the executable to debug, defaulting under the package's `.build/debug/` output dir.
---@return string
local function pick_program()
    local root = root_of(vim.api.nvim_get_current_buf())
    return vim.fn.input("Path to executable: ", root .. "/.build/debug/", "file")
end

--- The static `dap` field for the sourcekit-lsp server config (adapters + base configurations). The
--- lldb-dap adapter binary is resolved per-invocation against the current buffer's package root.
---@return table
function M.spec()
    return {
        adapters = {
            ["lldb-dap"] = {
                type = "executable",
                command = lldb_dap_bin(root_of(vim.api.nvim_get_current_buf())),
                name = "lldb-dap",
            },
            codelldb = codelldb_adapter(),
        },
        configurations = {
            swift = {
                {
                    type = "lldb-dap",
                    request = "launch",
                    name = "Debug executable (lldb-dap)",
                    program = pick_program,
                    cwd = "${workspaceFolder}",
                    stopOnEntry = false,
                },
                {
                    type = "codelldb",
                    request = "launch",
                    name = "Debug executable (CodeLLDB)",
                    program = pick_program,
                    cwd = "${workspaceFolder}",
                    stopOnEntry = false,
                },
            },
        },
    }
end

--- The `<Class>/<method>` filter for the XCTest method under the cursor (treesitter), or nil.
---@param bufnr integer
---@return string|nil filter, string|nil method
local function enclosing_test(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil, nil
    end
    local method, class
    while node do
        local t = node:type()
        if not method and t == "function_declaration" then
            local name_node = node:field("name")[1]
            local name = name_node and vim.treesitter.get_node_text(name_node, bufnr) or nil
            if not name or not name:match("^test") then
                return nil, nil
            end
            method = name
        elseif t == "class_declaration" then
            local name_node = node:field("name")[1]
            class = name_node and vim.treesitter.get_node_text(name_node, bufnr) or nil
            break
        end
        node = node:parent()
    end
    if not method then
        return nil, nil
    end
    return class and (class .. "/" .. method) or method, method
end

--- The XCTest bundle (`.build/debug/*.xctest`) SwiftPM builds for the package `root`, or nil. On
--- Linux the bundle IS an executable that accepts a test-filter argument; on macOS it is run through
--- `xcrun xctest` (surfaced with a hint when only the macOS bundle shape is found).
---@param root string
---@return string|nil
local function xctest_bundle(root)
    local hits = vim.fn.glob(root .. "/.build/debug/*.xctest", true, true)
    return type(hits) == "table" and hits[1] or nil
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

--- `:LvimLang debug-test` — build the test bundle (`swift build --build-tests`) and launch it under
--- lldb-dap, filtered to the XCTest method under the cursor. On Linux the `.xctest` bundle is an
--- executable that takes the `<Class>/<method>` filter as an argument.
---@param _args string[]
---@param ctx table
---@return nil
function M.debug_test(_args, ctx)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok then
        vim.notify("lvim-lang: lvim-dap not available", vim.log.levels.WARN, TITLE)
        return
    end
    local filter, method = enclosing_test(ctx.bufnr)
    if not filter then
        vim.notify("lvim-lang: cursor is not inside an XCTest test method", vim.log.levels.WARN, TITLE)
        return
    end
    local root = ctx.root or root_of(ctx.bufnr)
    local swift = toolchain.resolve("swift", "swift", root) or "swift"
    vim.notify("lvim-lang: building the test bundle…", vim.log.levels.INFO, TITLE)
    vim.system({ swift, "build", "--build-tests" }, { cwd = root, text = true }, function(res)
        vim.schedule(function()
            if res.code ~= 0 then
                vim.notify(
                    "lvim-lang: swift build --build-tests failed: " .. (res.stderr or ""),
                    vim.log.levels.ERROR,
                    TITLE
                )
                return
            end
            local bundle = xctest_bundle(root)
            if not bundle then
                vim.notify(
                    "lvim-lang: could not locate the .xctest bundle under .build/debug",
                    vim.log.levels.ERROR,
                    TITLE
                )
                return
            end
            dap.run({
                type = "lldb-dap",
                request = "launch",
                name = "Debug test " .. (method or filter),
                program = bundle,
                args = { filter },
                cwd = "${workspaceFolder}",
                stopOnEntry = false,
            })
        end)
    end)
end

return M
