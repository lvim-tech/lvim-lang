-- lvim-lang.providers.java.dap: Java debugging through lvim-dap, backed by java-debug.
-- Java debugging is driven BY the language server: jdtls loads the `java-debug` (and `java-test`)
-- bundles (their jars, globbed from the mason packages, are handed to jdtls via `init_options.bundles`
-- in servers/jdtls.lua) and then exposes a `vscode.java.startDebugSession` command that spins up a
-- debug server and returns its port. The DAP adapter here is therefore a `server` adapter whose
-- factory asks the attached jdtls client for that port — the canonical Eclipse JDT.LS debug seam, not
-- a side-channel. Base configurations cover launching a main class and attaching to a running JVM.
--
-- `:LvimLang debug` continues / starts a session. `:LvimLang debug-test` debugs exactly the JUnit
-- method under the cursor via the build tool's native remote-debug switch (Gradle `--debug-jvm` /
-- Maven `-Dmaven.surefire.debug`) — the test JVM suspends on the JDWP port and the debugger attaches.
--
---@module "lvim-lang.providers.java.dap"

local config = require("lvim-lang.config")
local buildtool = require("lvim-lang.providers.java.buildtool")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The Java provider's config block.
---@return table
local function opts()
    return config.providers.java or {}
end

--- The Java project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, {
            "settings.gradle",
            "settings.gradle.kts",
            "build.gradle",
            "build.gradle.kts",
            "pom.xml",
            ".git",
        }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The jar files a mason package ships under `extension/server/<pattern>`, or an empty list when the
--- package is not installed / lvim-pkg is unavailable. Used to feed jdtls its debug/test bundles.
---@param package string  mason package name
---@param pattern string  glob (relative to extension/server)
---@return string[]
local function server_jars(package, pattern)
    local ok, pkg = pcall(require, "lvim-pkg")
    if not ok or type(pkg.package_path) ~= "function" then
        return {}
    end
    local dir = pkg.package_path(package)
    if not dir or vim.fn.isdirectory(dir) ~= 1 then
        return {}
    end
    return vim.fn.glob(vim.fs.joinpath(dir, "extension", "server", pattern), true, true)
end

--- The jdtls bundle jars: the java-debug plugin (general debugging) plus the java-test runners
--- (single-test launching). Passed to jdtls as `init_options.bundles`. Empty until those mason
--- packages are installed — jdtls then simply has no debug/test commands (handled gracefully).
---@return string[]
function M.bundles()
    local bundles = {}
    vim.list_extend(bundles, server_jars("java-debug-adapter", "com.microsoft.java.debug.plugin-*.jar"))
    vim.list_extend(bundles, server_jars("java-test", "*.jar"))
    return bundles
end

--- The java-debug DAP adapter: a `server` adapter whose factory asks the attached jdtls client to
--- start a debug session (`vscode.java.startDebugSession`) and connects to the returned port.
---@return fun(callback: fun(adapter: table), config: table)
local function adapter()
    return function(callback, _config)
        local clients = vim.lsp.get_clients({ name = "jdtls" })
        local client = clients[1]
        if not client then
            vim.notify(
                "lvim-lang: jdtls is not attached — open a Java file so the debug bundle loads",
                vim.log.levels.WARN,
                TITLE
            )
            return
        end
        client:request("workspace/executeCommand", { command = "vscode.java.startDebugSession" }, function(err, port)
            if err or type(port) ~= "number" then
                vim.notify(
                    "lvim-lang: jdtls could not start a debug session (is java-debug-adapter installed?)",
                    vim.log.levels.ERROR,
                    TITLE
                )
                return
            end
            callback({ type = "server", host = "127.0.0.1", port = port })
        end)
    end
end

--- The static `dap` field for the jdtls server config (adapter + base configurations).
---@return table
function M.spec()
    local port = opts().debug_attach_port or 5005
    return {
        adapters = { java = adapter() },
        configurations = {
            java = {
                {
                    type = "java",
                    request = "launch",
                    name = "Launch (main class)",
                    mainClass = function()
                        return vim.fn.input("Main class (fully-qualified): ")
                    end,
                },
                {
                    type = "java",
                    request = "attach",
                    name = "Attach (JDWP " .. port .. ")",
                    hostName = "127.0.0.1",
                    port = port,
                },
            },
        },
    }
end

--- The enclosing test method + its class under the cursor, via treesitter (mirrors test.lua).
---@param bufnr integer
---@return string|nil class, string|nil method
local function enclosing(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil, nil
    end
    local class, method
    while node do
        local t = node:type()
        if t == "method_declaration" and not method then
            local n = node:field("name")[1]
            method = n and vim.treesitter.get_node_text(n, bufnr) or nil
        elseif t == "class_declaration" then
            local n = node:field("name")[1]
            class = n and vim.treesitter.get_node_text(n, bufnr) or class
        end
        node = node:parent()
    end
    return class, method
end

--- `:LvimLang debug` — resolve the project's MAIN classes from jdtls and launch one under the debugger
--- (a picker when several exist). Falls back to lvim-dap's own configuration picker — the base attach /
--- manual-launch configs — when jdtls is not attached yet or resolves no main class.
---@param _args string[]
---@param _ctx table
---@return nil
function M.debug(_args, _ctx)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok then
        vim.notify("lvim-lang: lvim-dap not available", vim.log.levels.WARN, TITLE)
        return
    end
    local client = vim.lsp.get_clients({ name = "jdtls" })[1]
    if not client then
        dap.continue() -- no jdtls yet → the static configurations (attach / input-based launch)
        return
    end
    client:request("workspace/executeCommand", { command = "vscode.java.resolveMainClass" }, function(err, res)
        if err or type(res) ~= "table" or #res == 0 then
            dap.continue() -- jdtls resolved no main class → fall back to the static configs
            return
        end
        --- Launch a discovered main class under the debugger.
        ---@param mc table  a resolveMainClass entry: { mainClass, projectName?, filePath? }
        local function launch(mc)
            dap.run({
                type = "java",
                request = "launch",
                name = "Launch " .. mc.mainClass,
                mainClass = mc.mainClass,
                projectName = mc.projectName,
            })
        end
        if #res == 1 then
            launch(res[1])
            return
        end
        -- Several main classes → the canonical centered picker.
        local icon = (opts().icons or {}).run or "󰐊"
        local items = {}
        for _, mc in ipairs(res) do
            items[#items + 1] = {
                label = mc.mainClass .. (mc.projectName and ("  (" .. mc.projectName .. ")") or ""),
                icon = icon,
            }
        end
        require("lvim-ui").select({
            title = "Debug — main class",
            items = items,
            callback = function(confirmed, idx)
                if confirmed and res[idx] then
                    launch(res[idx])
                end
            end,
        })
    end)
end

--- `:LvimLang debug-test` — debug exactly the JUnit method under the cursor. Starts the build tool's
--- test task for that method with remote debugging enabled (Gradle `--debug-jvm` / Maven
--- `-Dmaven.surefire.debug`) — the JVM suspends on the JDWP port — then attaches the debugger.
---@param _args string[]
---@param ctx table
---@return nil
function M.debug_test(_args, ctx)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok then
        vim.notify("lvim-lang: lvim-dap not available", vim.log.levels.WARN, TITLE)
        return
    end
    local class, method = enclosing(ctx.bufnr)
    if not (class and method) then
        vim.notify("lvim-lang: cursor is not inside a test method", vim.log.levels.WARN, TITLE)
        return
    end
    local root = ctx.root or root_of(ctx.bufnr)
    local tool = buildtool.detect(root)
    if not tool then
        vim.notify("lvim-lang: no Gradle or Maven project found", vim.log.levels.WARN, TITLE)
        return
    end
    local o = opts()
    local port = o.debug_attach_port or 5005
    -- Start the suspended test JVM listening on the JDWP port, then attach after it comes up.
    local cmd = buildtool.base(tool, root)
    if tool == "gradle" then
        vim.list_extend(cmd, { "test", "--tests", class .. "." .. method, "--debug-jvm" })
    else
        vim.list_extend(cmd, { "test", "-Dtest=" .. class .. "#" .. method, "-Dmaven.surefire.debug" })
    end
    require("lvim-lang.core.runner").run("java", {
        name = "debug test " .. class .. "." .. method,
        cmd = cmd,
        cwd = root,
        group = "Test",
        matcher = "generic",
    })
    -- The test JVM needs a moment to boot and open the JDWP socket before the debugger connects.
    local delay = o.debug_attach_delay_ms or 2000
    vim.defer_fn(function()
        dap.run({
            type = "java",
            request = "attach",
            name = "Debug test " .. class .. "." .. method,
            hostName = "127.0.0.1",
            port = port,
        })
    end, delay)
end

return M
