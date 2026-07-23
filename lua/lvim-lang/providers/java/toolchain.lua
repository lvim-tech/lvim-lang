-- lvim-lang.providers.java.toolchain: the Java toolchain spec.
-- Resolution order for `java` (first executable wins): an explicit `java_path` → a user lookup
-- command → a version manager (mise / asdf / SDKMAN honouring the project's pinned JDK) → PATH.
-- `jdtls` is the Eclipse JDT language server launcher (the mason `jdtls` package installs a `jdtls`
-- wrapper script): an explicit `jdtls_path` → the mason bin / PATH. Detection only — nothing is
-- installed here (missing tools come from the mason registry via the installer). NB: `java`
-- prints its version to STDERR, not stdout, so the version hook reads both streams.
--
---@module "lvim-lang.providers.java.toolchain"

local config = require("lvim-lang.config")

--- The java config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.java or {}
end

--- Run the user's `java_lookup_cmd` and take its first non-empty line as the java path.
---@return string|nil
local function lookup_java()
    local cmd = opts().java_lookup_cmd
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

--- SDKMAN keeps the selected JDK at `$SDKMAN_DIR/candidates/java/current/bin/java` (the `sdk`
--- command itself is a shell function, not an executable, so we read the symlinked `current`).
---@return string|nil
local function via_sdkman()
    local dir = vim.env.SDKMAN_DIR
    if not dir or dir == "" then
        return nil
    end
    local path = vim.fs.joinpath(dir, "candidates", "java", "current", "bin", "java")
    return vim.fn.executable(path) == 1 and path or nil
end

--- Resolve `java` through the configured version manager, honouring the project's pinned JDK for
--- `root`. `version_manager` may be a manager name ("mise"|"asdf"|"sdkman"), false to disable, or a
--- function(root) -> path|nil for a custom seam. Default: try mise, then asdf, then SDKMAN.
---@param root string
---@return string|nil
local function via_version_manager(root)
    local vm = opts().version_manager
    if vm == false then
        return nil
    end
    if type(vm) == "function" then
        return vm(root)
    end
    local managers = type(vm) == "string" and { vm } or { "mise", "asdf", "sdkman" }
    for _, mgr in ipairs(managers) do
        if mgr == "sdkman" then
            local path = via_sdkman()
            if path then
                return path
            end
        elseif vim.fn.executable(mgr) == 1 then
            -- `<mgr> which java` prints the resolved binary for the directory's pinned toolchain.
            local out = vim.fn.systemlist({ mgr, "which", "java" })
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

---@type LvimLangToolchainSpec
return {
    tools = {
        java = {
            {
                kind = "path",
                value = function()
                    return opts().java_path
                end,
            },
            { kind = "path", value = lookup_java },
            { kind = "path", value = via_version_manager },
            { kind = "which", value = "java" },
        },
        jdtls = {
            {
                kind = "path",
                value = function()
                    return opts().jdtls_path
                end,
            },
            { kind = "which", value = "jdtls" },
        },
    },

    --- Version string for a resolved tool. `java` (and the `jdtls` launcher, which wraps it) print
    --- `-version` to STDERR — so read both streams and return the first non-empty line, trimmed.
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
