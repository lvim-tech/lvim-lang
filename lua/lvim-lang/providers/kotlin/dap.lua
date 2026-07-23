-- lvim-lang.providers.kotlin.dap: Kotlin debugging through lvim-dap, backed by kotlin-debug-adapter.
-- Unlike jdtls (where debugging lives INSIDE the language server via bundles), the Kotlin debug
-- adapter (fwcd/kotlin-debug-adapter) is a STANDALONE DAP server executable — a VS Code protocol
-- interpreter over stdio — so the adapter here is a plain `executable` adapter, resolved per project
-- root through core.toolchain at launch time (mirrors the csharp/netcoredbg model). It drives the
-- Gradle build itself for a `launch` (given a `projectRoot` + `mainClass`) and can also `attach` to a
-- running JVM over JDWP.
--
-- `:LvimLang debug` continues / starts a session. `:LvimLang debug-test` debugs exactly the JUnit
-- method under the cursor via the build tool's native remote-debug switch (Gradle `--debug-jvm` /
-- Maven `-Dmaven.surefire.debug`) — the test JVM suspends on the JDWP port and the debugger attaches.
--
---@module "lvim-lang.providers.kotlin.dap"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local buildtool = require("lvim-lang.providers.kotlin.buildtool")

local TITLE = { title = "lvim-lang" }

-- Kotlin's project-root markers (Gradle scripts / wrapper, then `.git`).
---@type string[]
local ROOT_PATTERNS = {
    "build.gradle.kts",
    "build.gradle",
    "settings.gradle.kts",
    "settings.gradle",
    ".git",
}

local M = {}

--- The Kotlin provider's config block.
---@return table
local function opts()
    return config.providers.kotlin or {}
end

--- The Kotlin project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, ROOT_PATTERNS) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Resolve the kotlin-debug-adapter binary: an explicit config path → the mason install → PATH.
---@return string
local function adapter_bin()
    local root = vim.uv.cwd() or "."
    return toolchain.resolve("kotlin", "kotlin-debug-adapter", root) or "kotlin-debug-adapter"
end

--- The kotlin-debug-adapter DAP adapter (a stdio DAP server executable).
---@return table
local function adapter()
    return {
        type = "executable",
        command = adapter_bin(),
        -- The adapter speaks DAP straight over stdio; no interpreter flag is required.
        args = {},
    }
end

--- The static `dap` field for the language server config (adapter + base configurations).
---@return table
function M.spec()
    local port = opts().debug_attach_port or 5005
    return {
        adapters = { kotlin = adapter() },
        configurations = {
            kotlin = {
                {
                    type = "kotlin",
                    request = "launch",
                    name = "Launch (main class)",
                    projectRoot = "${workspaceFolder}",
                    mainClass = function()
                        return vim.fn.input("Main class (fully-qualified, e.g. MainKt): ")
                    end,
                },
                {
                    type = "kotlin",
                    request = "attach",
                    name = "Attach (JDWP " .. port .. ")",
                    hostName = "127.0.0.1",
                    port = port,
                    timeout = opts().debug_attach_delay_ms or 2000,
                },
            },
        },
    }
end

--- The enclosing test function + its class under the cursor, via treesitter (mirrors test.lua). The
--- Kotlin grammar names a function with a `simple_identifier` and a class with a `type_identifier`.
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
        if t == "function_declaration" and not method then
            for child in node:iter_children() do
                if child:type() == "simple_identifier" then
                    method = vim.treesitter.get_node_text(child, bufnr)
                    break
                end
            end
        elseif t == "class_declaration" or t == "object_declaration" then
            for child in node:iter_children() do
                if child:type() == "type_identifier" then
                    class = vim.treesitter.get_node_text(child, bufnr)
                    break
                end
            end
        end
        node = node:parent()
    end
    return class, method
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
        vim.notify("lvim-lang: cursor is not inside a test function", vim.log.levels.WARN, TITLE)
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
    require("lvim-lang.core.runner").run("kotlin", {
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
            type = "kotlin",
            request = "attach",
            name = "Debug test " .. class .. "." .. method,
            hostName = "127.0.0.1",
            port = port,
            timeout = delay,
        })
    end, delay)
end

return M
