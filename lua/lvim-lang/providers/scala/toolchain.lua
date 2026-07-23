-- lvim-lang.providers.scala.toolchain: the Scala toolchain spec.
-- Resolution order for the build / JDK tools (`sbt`, `mill`, `java`) — first executable wins: an
-- explicit path (`sbt_path` / `mill_path` / `java_path`) → a user lookup command → a version manager
-- (mise / asdf / SDKMAN honouring the project's pinned toolchain) → PATH. SDKMAN is the common sbt /
-- JDK manager, so it is honoured for each (sbt / java are SDKMAN candidates; mill is not, so its
-- SDKMAN lookup is skipped and it falls through to PATH). The tooling binaries — `metals`, `scalafmt`
-- — and `bloop` resolve from an explicit path → the mason bin / PATH (metals / scalafmt are installed
-- on demand from the mason registry; bloop is the user's own coursier install). Detection only;
-- nothing is installed here. NB: `java` prints `-version` to STDERR, so the version hook reads both
-- streams.
--
---@module "lvim-lang.providers.scala.toolchain"

local config = require("lvim-lang.config")

--- The scala config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.scala or {}
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
--- `current`). `candidate` is the SDKMAN candidate name (java / sbt), `bin` the binary; a nil
--- candidate (e.g. mill, not a SDKMAN candidate) skips SDKMAN.
---@param candidate string|nil
---@param bin string
---@return string|nil
local function via_sdkman(candidate, bin)
    if not candidate then
        return nil
    end
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
--- `candidate` is the SDKMAN candidate name for `bin` (java / sbt), or nil when `bin` is not one.
---@param bin string
---@param candidate string|nil
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

--- The ordered strategies for a build / JDK tool that honours the version manager: explicit path →
--- lookup command → version manager → PATH.
---@param path_key string     config key for an explicit path
---@param lookup_key string|nil config key for a lookup command (nil = no lookup step)
---@param bin string          the binary name
---@param candidate string|nil the SDKMAN candidate name (nil = not a SDKMAN candidate)
---@return LvimLangToolchainStrategy[]
local function sdk_tool(path_key, lookup_key, bin, candidate)
    local strategies = {
        {
            kind = "path",
            value = function()
                return opts()[path_key]
            end,
        },
    }
    if lookup_key then
        strategies[#strategies + 1] = {
            kind = "path",
            value = function()
                return lookup(lookup_key)
            end,
        }
    end
    strategies[#strategies + 1] = {
        kind = "path",
        value = function(root)
            return via_version_manager(bin, candidate, root)
        end,
    }
    strategies[#strategies + 1] = { kind = "which", value = bin }
    return strategies
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
        sbt = sdk_tool("sbt_path", "sbt_lookup_cmd", "sbt", "sbt"),
        mill = sdk_tool("mill_path", "mill_lookup_cmd", "mill", nil),
        java = sdk_tool("java_path", "java_lookup_cmd", "java", "java"),
        metals = tool_bin("metals_path", "metals"),
        scalafmt = tool_bin("scalafmt_path", "scalafmt"),
        bloop = tool_bin("bloop_path", "bloop"),
    },

    --- Version string for a resolved tool. `java` prints `-version` to STDERR; the build tools print
    --- to STDOUT — so read both streams and return the first non-empty line, trimmed. `sbt --version`
    --- can be slow to boot, so `java` is the one the health section reads for a version.
    ---@param bin string
    ---@return string|nil
    version = function(bin)
        -- `-version` covers java / sbt; mill uses `--version`. Try `-version` first, then `--version`.
        local res = vim.system({ bin, "-version" }, { text = true }):wait()
        if res.code ~= 0 then
            res = vim.system({ bin, "--version" }, { text = true }):wait()
        end
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
