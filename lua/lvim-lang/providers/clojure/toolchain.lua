-- lvim-lang.providers.clojure.toolchain: the Clojure toolchain spec.
-- Resolution order for the SDK tools (`clojure`, `clj`, `lein`, `boot`, `java`) — first executable
-- wins: an explicit path (`clojure_path` / `clj_path` / `lein_path` / `boot_path` / `java_path`) → a
-- user lookup command → a version manager (mise / asdf honouring the project's pinned toolchain;
-- SDKMAN for `lein` / `java`, the candidates it ships) → PATH. The tooling binaries —
-- `clojure-lsp`, `cljfmt`, `clj-kondo` — resolve from an explicit path → the mason bin / PATH (they
-- are installed on demand from the mason registry). Detection only; nothing is installed here. NB:
-- `java` prints `-version` to STDERR, so the version hook reads both streams.
--
---@module "lvim-lang.providers.clojure.toolchain"

local config = require("lvim-lang.config")

--- The clojure config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.clojure or {}
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
--- `current`). `candidate` is the SDKMAN candidate name (java / leiningen), `bin` the binary.
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
--- `candidate` is the SDKMAN candidate name for `bin` (java / leiningen), or nil when SDKMAN ships
--- none for it (the Clojure CLI / Boot) — then the SDKMAN branch is skipped.
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
            if candidate then
                local path = via_sdkman(candidate, bin)
                if path then
                    return path
                end
            end
        elseif vim.fn.executable(mgr) == 1 then
            -- `<mgr> which <bin>` prints the resolved binary for the directory's pinned toolchain.
            local out = vim.system({ mgr, "which", bin }, { cwd = root, text = true }):wait()
            if out.code == 0 then
                local path = vim.trim(out.stdout or "")
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
---@param path_key string      config key for an explicit path
---@param lookup_key string    config key for a lookup command
---@param bin string           the binary name
---@param candidate string|nil the SDKMAN candidate name (nil = SDKMAN ships none)
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
        -- The Clojure CLI ships two binaries: `clojure` (scripting) and `clj` (the rlwrap REPL wrapper).
        clojure = sdk_tool("clojure_path", "clojure_lookup_cmd", "clojure", nil),
        clj = sdk_tool("clj_path", "clojure_lookup_cmd", "clj", nil),
        lein = sdk_tool("lein_path", "lein_lookup_cmd", "lein", "leiningen"),
        boot = sdk_tool("boot_path", "boot_lookup_cmd", "boot", nil),
        java = sdk_tool("java_path", "java_lookup_cmd", "java", "java"),
        ["clojure-lsp"] = tool_bin("clojure_lsp_path", "clojure-lsp"),
        cljfmt = tool_bin("cljfmt_path", "cljfmt"),
        ["clj-kondo"] = tool_bin("clj_kondo_path", "clj-kondo"),
    },

    --- Version string for a resolved tool. Most Clojure tools use `--version` and print to STDOUT,
    --- while `java` prints `-version` to STDERR — so read BOTH streams and return the first non-empty
    --- line, trimmed. (`clojure --version` → the CLI version; `java --version` → the JDK banner.)
    ---@param bin string
    ---@return string|nil
    version = function(bin)
        local res = vim.system({ bin, "--version" }, { text = true }):wait()
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
