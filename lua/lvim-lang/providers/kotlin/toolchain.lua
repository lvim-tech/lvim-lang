-- lvim-lang.providers.kotlin.toolchain: the Kotlin toolchain spec.
-- Resolution order for the SDK tools (`kotlin`, `kotlinc`, `gradle`, `java`) — first executable wins:
-- an explicit path (`kotlin_path` / `kotlinc_path` / `gradle_path` / `java_path`) → a user lookup
-- command → a version manager (mise / asdf / SDKMAN honouring the project's pinned toolchain) → PATH.
-- SDKMAN is the common Kotlin/Gradle/JDK manager, so it is honoured for each of them. The tooling
-- binaries — `kotlin-language-server`, `ktlint`, `kotlin-debug-adapter` — resolve from an explicit
-- path → the mason bin / PATH (they are installed on demand from the mason registry). Detection only;
-- nothing is installed here. NB: `kotlin` / `kotlinc` / `java` print `-version` to STDERR, so the
-- version hook reads both streams.
--
---@module "lvim-lang.providers.kotlin.toolchain"

local config = require("lvim-lang.config")

--- The kotlin config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.kotlin or {}
end

--- Run a user lookup command (config key `opt_key`) and take its first non-empty line as a path.
---@param opt_key string
---@return string|nil
local function lookup(opt_key)
    local cmd = opts()[opt_key]
    if type(cmd) ~= "string" or cmd == "" then
        return nil
    end
    local out = vim.fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 or type(out) ~= "table" then
        return nil
    end
    for _, line in ipairs(out) do
        local trimmed = vim.trim(line)
        if trimmed ~= "" then
            return trimmed
        end
    end
    return nil
end

--- SDKMAN keeps the selected candidate at `$SDKMAN_DIR/candidates/<candidate>/current/bin/<bin>`
--- (the `sdk` command itself is a shell function, not an executable, so we read the symlinked
--- `current`). `candidate` is the SDKMAN candidate name (java / kotlin / gradle), `bin` the binary.
---@param candidate string
---@param bin string
---@return string|nil
local function via_sdkman(candidate, bin)
    local dir = vim.env.SDKMAN_DIR
    if not dir or dir == "" then
        return nil
    end
    local path = vim.fs.joinpath(dir, "candidates", candidate, "current", "bin", bin)
    return vim.fn.executable(path) == 1 and path or nil
end

--- Resolve `bin` through the configured version manager for `root`, honouring the project's pinned
--- toolchain. `version_manager` may be a manager name ("mise"|"asdf"|"sdkman"), false to disable, or
--- a function(root, bin) -> path|nil for a custom seam. Default: try mise, then asdf, then SDKMAN.
--- `candidate` is the SDKMAN candidate name for `bin` (java/kotlin/gradle).
---@param bin string
---@param candidate string
---@param root string
---@return string|nil
local function via_version_manager(bin, candidate, root)
    local vm = opts().version_manager
    if vm == false then
        return nil
    end
    if type(vm) == "function" then
        return vm(root, bin)
    end
    local managers = type(vm) == "string" and { vm } or { "mise", "asdf", "sdkman" }
    for _, mgr in ipairs(managers) do
        if mgr == "sdkman" then
            local path = via_sdkman(candidate, bin)
            if path then
                return path
            end
        elseif vim.fn.executable(mgr) == 1 then
            -- `<mgr> which <bin>` prints the resolved binary for the directory's pinned toolchain.
            local out = vim.fn.systemlist({ mgr, "which", bin })
            if vim.v.shell_error == 0 and type(out) == "table" and out[1] then
                local path = vim.trim(out[1])
                if path ~= "" and vim.fn.executable(path) == 1 then
                    return path
                end
            end
        end
    end
    return nil
end

--- The ordered strategies for an SDK tool that honours the version manager: explicit path → lookup
--- command → version manager → PATH.
---@param path_key string   config key for an explicit path
---@param lookup_key string config key for a lookup command
---@param bin string        the binary name
---@param candidate string  the SDKMAN candidate name
---@return LvimLangToolchainStrategy[]
local function sdk_tool(path_key, lookup_key, bin, candidate)
    return {
        {
            kind = "path",
            value = function()
                return opts()[path_key]
            end,
        },
        {
            kind = "path",
            value = function()
                return lookup(lookup_key)
            end,
        },
        {
            kind = "path",
            value = function(root)
                return via_version_manager(bin, candidate, root)
            end,
        },
        { kind = "which", value = bin },
    }
end

--- The strategies for an on-demand tool binary: an explicit path → the mason bin / PATH.
---@param path_key string
---@param bin string
---@return LvimLangToolchainStrategy[]
local function tool_bin(path_key, bin)
    return {
        {
            kind = "path",
            value = function()
                return opts()[path_key]
            end,
        },
        { kind = "which", value = bin },
    }
end

---@type LvimLangToolchainSpec
return {
    tools = {
        kotlin = sdk_tool("kotlin_path", "kotlin_lookup_cmd", "kotlin", "kotlin"),
        kotlinc = sdk_tool("kotlinc_path", "kotlin_lookup_cmd", "kotlinc", "kotlin"),
        gradle = sdk_tool("gradle_path", "gradle_lookup_cmd", "gradle", "gradle"),
        java = sdk_tool("java_path", "java_lookup_cmd", "java", "java"),
        ["kotlin-language-server"] = tool_bin("kotlin_language_server_path", "kotlin-language-server"),
        ktlint = tool_bin("ktlint_path", "ktlint"),
        ["kotlin-debug-adapter"] = tool_bin("kotlin_debug_adapter_path", "kotlin-debug-adapter"),
    },

    --- Version string for a resolved tool. `kotlin` / `kotlinc` / `java` (and `gradle`) print their
    --- version banner to STDERR or STDOUT depending on the tool — so read both streams and return the
    --- first non-empty line, trimmed.
    ---@param bin string
    ---@return string|nil
    version = function(bin)
        local res = vim.system({ bin, "-version" }, { text = true }):wait()
        local text = (res.stderr or "") .. "\n" .. (res.stdout or "")
        for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
            local trimmed = vim.trim(line)
            if trimmed ~= "" then
                return trimmed
            end
        end
        return nil
    end,
}
