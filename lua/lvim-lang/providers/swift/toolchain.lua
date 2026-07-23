-- lvim-lang.providers.swift.toolchain: the Swift toolchain spec.
-- Swift is the USER's toolchain (installed through Xcode / swiftly / a Linux tarball on PATH); it is
-- never a mason package, and neither is `sourcekit-lsp` — the language server ships INSIDE the Swift
-- toolchain, beside `swift` in the same bin dir (the same "server bundled with the SDK" shape as
-- dartls). Resolution for each tool (first executable wins): an explicit config path → a user lookup
-- command → a version manager (mise/asdf, honouring a project pin) → PATH, with sourcekit-lsp / lldb
-- additionally derived from the resolved Swift toolchain's bin dir. swiftformat / lldb-dap are the
-- installable tools (an explicit path → the mason bin → PATH). Detection only: nothing is installed
-- here (missing swiftformat / lldb-dap come from the mason registry through the installer).
--
---@module "lvim-lang.providers.swift.toolchain"

local config = require("lvim-lang.config")

--- The swift config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.swift or {}
end

--- Run the user's `swift_lookup_cmd` and take its first non-empty line as the swift path (the seam
--- for swiftly and other managers that print a resolved binary path — e.g. `swiftly use --print-location`).
---@return string|nil
local function lookup_swift()
    local cmd = opts().swift_lookup_cmd
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

--- Resolve `swift` through the configured version manager (mise/asdf), honouring the project's
--- pinned toolchain for `root`. `version_manager` may be a manager name ("mise"|"asdf"), false to
--- disable, or a function(root) -> path|nil for a custom seam (e.g. swiftly). Default: try mise then asdf.
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
    local managers = type(vm) == "string" and { vm } or { "mise", "asdf" }
    for _, mgr in ipairs(managers) do
        if vim.fn.executable(mgr) == 1 then
            -- `<mgr> which swift` prints the binary for the directory's pinned toolchain; run in `root`
            -- so a project's `.mise.toml` / `.tool-versions` Swift pin wins.
            local out = vim.system({ mgr, "which", "swift" }, { cwd = root, text = true }):wait()
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

--- The `bin` that sits beside the resolved `swift` in the same toolchain bin dir (sourcekit-lsp and
--- the toolchain's own lldb both live there), or nil.
---@param bin string  "sourcekit-lsp" | "lldb-dap"
---@return fun(root: string): string|nil
local function beside_swift(bin)
    return function(root)
        local swift = require("lvim-lang.core.toolchain").resolve("swift", "swift", root)
        if not swift then
            return nil
        end
        local path = vim.fs.joinpath(vim.fs.dirname(swift), bin)
        return vim.fn.executable(path) == 1 and path or nil
    end
end

--- Build a resolver that returns an explicit config path for `key` (e.g. "swift_path"), or nil.
---@param key string
---@return fun(): string|nil
local function explicit(key)
    return function()
        return opts()[key]
    end
end

--- The `bin` inside the resolved mason bin dir, if installed there (lvim-pkg owns the path — the
--- same dir the installer writes swiftformat / lldb-dap into). nil when unavailable.
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
        -- The Swift compiler / package driver: an explicit path → a lookup command → the version
        -- manager (honouring a project pin) → PATH.
        swift = {
            { kind = "path", value = explicit("swift_path") },
            { kind = "path", value = lookup_swift },
            { kind = "path", value = via_version_manager },
            { kind = "which", value = "swift" },
        },
        -- The language server ships with the toolchain: an explicit path → beside `swift` → PATH.
        ["sourcekit-lsp"] = {
            { kind = "path", value = explicit("sourcekit_lsp_path") },
            { kind = "path", value = beside_swift("sourcekit-lsp") },
            { kind = "which", value = "sourcekit-lsp" },
        },
        -- The formatter: an explicit path → the mason bin → PATH.
        swiftformat = {
            { kind = "path", value = explicit("swiftformat_path") },
            { kind = "path", value = in_mason("swiftformat") },
            { kind = "which", value = "swiftformat" },
        },
        -- The debug adapter: an explicit path → the mason bin → the toolchain's own lldb-dap → PATH.
        ["lldb-dap"] = {
            { kind = "path", value = explicit("lldb_dap_path") },
            { kind = "path", value = in_mason("lldb-dap") },
            { kind = "path", value = beside_swift("lldb-dap") },
            { kind = "which", value = "lldb-dap" },
        },
    },

    --- `<bin> --version` — first NON-EMPTY line, trimmed. `swift --version` prints the toolchain
    --- banner; swiftformat / lldb-dap accept `--version` too. (sourcekit-lsp has no stable
    --- version flag, so it reports no version — presence is what health checks.)
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
