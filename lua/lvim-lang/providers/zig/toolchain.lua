-- lvim-lang.providers.zig.toolchain: the Zig toolchain spec.
-- Zig ships as ONE self-contained binary — `zig` is the compiler, build system, test runner AND
-- formatter (`zig fmt` is a subcommand, not a separate tool). Resolution for `zig` (first executable
-- wins): an explicit config.zig_path → a user lookup command → a version manager (mise / asdf, which
-- honour a project's .tool-versions / mise.toml) → PATH. `zls` (the language server) and `lldb-dap`
-- (the debug adapter) are mason packages: an explicit path → the mason bin dir (where lvim-installer
-- drops them) → PATH. Detection only — nothing is installed here.
--
---@module "lvim-lang.providers.zig.toolchain"

local config = require("lvim-lang.config")

--- The zig config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.zig or {}
end

--- Run the user's `zig_lookup_cmd` and take its first non-empty line as the zig path.
---@return string|nil
local function lookup_zig()
    local cmd = opts().zig_lookup_cmd
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

--- Resolve `zig` through the configured version manager (mise / asdf), honouring the project's
--- pinned version for `root`. `version_manager` may be a manager name ("mise"|"asdf"), false to
--- disable, or a function(root) -> path|nil for a custom seam. Default: try mise then asdf.
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
    -- `<mgr> which zig` prints the resolved binary for the directory's pinned toolchain. Run in
    -- `root` so a project-pinned Zig (.tool-versions / mise.toml) wins over a global default.
    local managers = type(vm) == "string" and { vm } or { "mise", "asdf" }
    for _, mgr in ipairs(managers) do
        if vim.fn.executable(mgr) == 1 then
            local out = vim.system({ mgr, "which", "zig" }, { cwd = root, text = true }):wait()
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

--- Build a resolver that returns an explicit config path for `key` (e.g. "zig_path"), or nil.
---@param key string
---@return fun(): string|nil
local function explicit(key)
    return function()
        return opts()[key]
    end
end

--- The `bin` inside the resolved mason bin dir, if installed there (lvim-pkg owns the path — the
--- same dir the installer writes zls / lldb-dap into). nil when unavailable.
---@param bin string
---@return fun(): string|nil
local function in_mason(bin)
    return function()
        local ok, pkg = pcall(require, "lvim-pkg")
        if not ok or type(pkg.bin_dir) ~= "function" then
            return nil
        end
        local path = vim.fs.joinpath(pkg.bin_dir(), bin)
        return vim.fn.executable(path) == 1 and path or nil
    end
end

---@type LvimLangToolchainSpec
return {
    tools = {
        zig = {
            { kind = "path", value = explicit("zig_path") },
            { kind = "path", value = lookup_zig },
            { kind = "path", value = via_version_manager },
            { kind = "which", value = "zig" },
        },
        zls = {
            { kind = "path", value = explicit("zls_path") },
            { kind = "path", value = in_mason("zls") },
            { kind = "which", value = "zls" },
        },
        ["lldb-dap"] = {
            { kind = "path", value = explicit("lldb_dap_path") },
            { kind = "path", value = in_mason("lldb-dap") },
            { kind = "which", value = "lldb-dap" },
        },
    },

    --- Version string for a resolved tool. Zig is the ODD one out: `zig version` is a SUBCOMMAND
    --- (`zig --version` errors), while zls / lldb-dap use the conventional `--version`. Dispatch on
    --- the binary basename so each tool is asked the right way; first NON-EMPTY line, trimmed.
    ---@param bin string
    ---@return string|nil
    version = function(bin)
        local base = vim.fs.basename(bin)
        -- The zig binary (but NOT zls) wants the `version` subcommand.
        local argv = (base:match("zig") and not base:match("zls")) and { bin, "version" } or { bin, "--version" }
        local out = vim.fn.systemlist(argv)
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
    end,
}
