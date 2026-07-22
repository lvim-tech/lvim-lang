-- lvim-lang.providers.rust.toolchain: the Rust toolchain spec.
-- Rust toolchains are managed by rustup (and often surfaced through mise / asdf). Resolution order
-- for each tool (first executable wins): an explicit config path → a user lookup command → the
-- version manager (`rustup which <tool>`, which honours a project's rust-toolchain.toml; then mise /
-- asdf) → PATH. rust-analyzer additionally falls back to the mason bin (a github release) when the
-- toolchain does not ship it as a component. Detection only — nothing is installed here.
--
---@module "lvim-lang.providers.rust.toolchain"

local config = require("lvim-lang.config")

--- The rust config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.rust or {}
end

--- Run the user's `cargo_lookup_cmd` and take its first non-empty line as the cargo path.
---@return string|nil
local function lookup_cargo()
    local cmd = opts().cargo_lookup_cmd
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

--- Resolve `tool` through the configured version manager, honouring the project's pinned toolchain
--- for `root`. `version_manager` may be a manager name ("rustup"|"mise"|"asdf"), false to disable, or
--- a function(root, tool) -> path|nil. Default: try rustup (`rustup which <tool>`) then mise/asdf.
---@param tool string
---@param root string
---@return string|nil
local function via_version_manager(tool, root)
    local vm = opts().version_manager
    if vm == false then
        return nil
    end
    if type(vm) == "function" then
        return vm(root, tool)
    end
    local managers = type(vm) == "string" and { vm } or { "rustup", "mise", "asdf" }
    for _, mgr in ipairs(managers) do
        if vim.fn.executable(mgr) == 1 then
            -- `rustup which <tool>` prints the active toolchain's binary; `mise/asdf which <tool>` the
            -- pinned one. Run in `root` so a project toolchain (rust-toolchain.toml / .tool-versions) wins.
            local out = vim.system({ mgr, "which", tool }, { cwd = root, text = true }):wait()
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

--- Build a resolver that returns an explicit config path for `key` (e.g. "cargo_path"), or nil.
---@param key string
---@return fun(): string|nil
local function explicit(key)
    return function()
        return opts()[key]
    end
end

--- Build a version-manager resolver for `tool`.
---@param tool string
---@return fun(root: string): string|nil
local function vm(tool)
    return function(root)
        return via_version_manager(tool, root)
    end
end

--- The rust-analyzer binary inside the resolved mason bin dir, if installed there.
---@return string|nil
local function ra_in_mason()
    local ok, pkg = pcall(require, "lvim-pkg")
    if not ok or type(pkg.bin_dir) ~= "function" then
        return nil
    end
    local path = vim.fs.joinpath(pkg.bin_dir(), "rust-analyzer")
    return vim.fn.executable(path) == 1 and path or nil
end

---@type LvimLangToolchainSpec
return {
    tools = {
        cargo = {
            { kind = "path", value = explicit("cargo_path") },
            { kind = "path", value = lookup_cargo },
            { kind = "path", value = vm("cargo") },
            { kind = "which", value = "cargo" },
        },
        rustc = {
            { kind = "path", value = explicit("rustc_path") },
            { kind = "path", value = vm("rustc") },
            { kind = "which", value = "rustc" },
        },
        ["rust-analyzer"] = {
            { kind = "path", value = explicit("rust_analyzer_path") },
            { kind = "path", value = vm("rust-analyzer") },
            { kind = "path", value = ra_in_mason },
            { kind = "which", value = "rust-analyzer" },
        },
        rustfmt = {
            { kind = "path", value = vm("rustfmt") },
            { kind = "which", value = "rustfmt" },
        },
        clippy = {
            -- the clippy driver is `cargo-clippy` (invoked as `cargo clippy`).
            { kind = "path", value = vm("cargo-clippy") },
            { kind = "which", value = "cargo-clippy" },
        },
    },

    --- `<bin> --version` — first NON-EMPTY line, trimmed (Rust tools use `--version`).
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
