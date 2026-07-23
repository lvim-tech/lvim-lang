-- lvim-lang.providers.csharp.toolchain: the C# / .NET toolchain spec.
-- Resolution order for `dotnet` (first executable wins): an explicit config.dotnet_path → a user
-- lookup command → a version-manager (mise/asdf) resolution honouring the project's pinned SDK →
-- PATH. The language server (`OmniSharp` by default, `roslyn` optional), the `csharpier` formatter
-- and the `netcoredbg` debugger are mason-registry binaries: an explicit path → the resolved mason
-- bin directory (where the installer drops them) → PATH. Detection only — nothing is installed here
-- (missing tools come from the mason registry via the installer / core.ensure).
--
---@module "lvim-lang.providers.csharp.toolchain"

local config = require("lvim-lang.config")

--- The csharp config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.csharp or {}
end

--- Run the user's `dotnet_lookup_cmd` and take its first non-empty line as the dotnet path.
---@return string|nil
local function lookup_dotnet()
    local cmd = opts().dotnet_lookup_cmd
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

--- Resolve `dotnet` through the configured version manager (mise/asdf), honouring the project's
--- pinned SDK for `root`. `version_manager` may be a manager name ("mise"|"asdf"), false to disable,
--- or a function(root) -> path|nil for a custom seam. Default: try mise then asdf.
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
    -- `<mgr> which dotnet` prints the resolved binary for the directory's pinned toolchain.
    local managers = type(vm) == "string" and { vm } or { "mise", "asdf" }
    for _, mgr in ipairs(managers) do
        if vim.fn.executable(mgr) == 1 then
            local out = vim.system({ mgr, "which", "dotnet" }, { cwd = root, text = true }):wait()
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

--- Build a resolver that returns an explicit config path for `key` (e.g. "dotnet_path"), or nil.
---@param key string
---@return fun(): string|nil
local function explicit(key)
    return function()
        return opts()[key]
    end
end

--- Build a resolver for a mason-installed binary `bin`: the binary inside lvim-pkg's mason bin
--- directory when installed there, else nil (PATH is a separate strategy).
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
        dotnet = {
            { kind = "path", value = explicit("dotnet_path") },
            { kind = "path", value = lookup_dotnet },
            { kind = "path", value = via_version_manager },
            { kind = "which", value = "dotnet" },
        },
        OmniSharp = {
            { kind = "path", value = explicit("omnisharp_path") },
            { kind = "path", value = in_mason("OmniSharp") },
            { kind = "which", value = "OmniSharp" },
        },
        -- The roslyn language server (Microsoft.CodeAnalysis.LanguageServer) — optional, opt-in.
        ["Microsoft.CodeAnalysis.LanguageServer"] = {
            { kind = "path", value = explicit("roslyn_path") },
            { kind = "path", value = in_mason("Microsoft.CodeAnalysis.LanguageServer") },
            { kind = "which", value = "Microsoft.CodeAnalysis.LanguageServer" },
        },
        csharpier = {
            { kind = "path", value = explicit("csharpier_path") },
            { kind = "path", value = in_mason("csharpier") },
            { kind = "which", value = "csharpier" },
        },
        netcoredbg = {
            { kind = "path", value = explicit("netcoredbg_path") },
            { kind = "path", value = in_mason("netcoredbg") },
            { kind = "which", value = "netcoredbg" },
        },
    },

    --- `<bin> --version` — first NON-EMPTY line, trimmed. dotnet / OmniSharp / csharpier / netcoredbg
    --- all report their version with `--version`.
    ---@param bin string
    ---@return string|nil
    version = function(bin)
        local out = vim.fn.systemlist({ bin, "--version" })
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
