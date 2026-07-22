-- lvim-lang.providers.typescript.toolchain: the TypeScript / JavaScript toolchain spec.
-- JS/TS tooling is PROJECT-LOCAL first: a repo pins its own prettier / eslint / tsc / vitest under
-- `node_modules/.bin`, and those must win over a shared copy — the analog of Python's venv-awareness.
-- So the efm / codegen / test binaries resolve `<root>/node_modules/.bin/<bin>` first, then the mason
-- bin, then PATH. The language servers (vtsls, the eslint LSP) are editor tools resolved from mason /
-- PATH (with node_modules kept as a low-priority fallback). `node` resolves through the version
-- manager (mise / asdf / fnm, honouring the project's pin) then PATH. Detection only.
--
---@module "lvim-lang.providers.typescript.toolchain"

local config = require("lvim-lang.config")

--- The typescript config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.typescript or {}
end

--- Run the user's `node_lookup_cmd` and take its first non-empty line as the node path.
---@return string|nil
local function lookup_node()
    local cmd = opts().node_lookup_cmd
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

--- Resolve `node` through the configured version manager, honouring the project's pin for `root`.
--- `version_manager` may be a name ("mise"|"asdf"|"fnm"), false to disable, or a function(root).
--- Default: try mise then asdf then fnm (`<mgr> which node`).
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
    local managers = type(vm) == "string" and { vm } or { "mise", "asdf", "fnm" }
    for _, mgr in ipairs(managers) do
        if vim.fn.executable(mgr) == 1 then
            local out = vim.system({ mgr, "which", "node" }, { cwd = root, text = true }):wait()
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

--- Build a resolver that returns the explicit config path under `key`, or nil.
---@param key string
---@return fun(): string|nil
local function explicit(key)
    return function()
        return opts()[key]
    end
end

--- Resolve a tool `bin` inside the project's `node_modules/.bin` (walked up from the root), if
--- executable — so a project-pinned prettier / eslint / tsc / vitest wins over a shared copy.
---@param bin string
---@return fun(root: string): string|nil
local function in_node_modules(bin)
    return function(root)
        local pkg = vim.fs.root(root, { "package.json" }) or root
        local p = vim.fs.joinpath(pkg, "node_modules", ".bin", bin)
        return vim.fn.executable(p) == 1 and p or nil
    end
end

--- Resolve a tool `bin` inside the mason bin directory (lvim-pkg), if installed there.
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
        node = {
            { kind = "path", value = explicit("node_path") },
            { kind = "path", value = lookup_node },
            { kind = "path", value = via_version_manager },
            { kind = "which", value = "node" },
        },
        -- LSP servers: mason / PATH first (editor tools), a project-local copy only as a fallback.
        vtsls = {
            { kind = "path", value = explicit("vtsls_path") },
            { kind = "path", value = in_mason("vtsls") },
            { kind = "path", value = in_node_modules("vtsls") },
            { kind = "which", value = "vtsls" },
        },
        ["eslint-lsp"] = {
            { kind = "path", value = explicit("eslint_lsp_path") },
            { kind = "path", value = in_mason("vscode-eslint-language-server") },
            { kind = "which", value = "vscode-eslint-language-server" },
        },
        -- efm / codegen / test binaries: PROJECT-LOCAL first, then mason, then PATH.
        prettier = {
            { kind = "path", value = explicit("prettier_path") },
            { kind = "path", value = in_node_modules("prettier") },
            { kind = "path", value = in_mason("prettier") },
            { kind = "which", value = "prettier" },
        },
        tsc = {
            { kind = "path", value = in_node_modules("tsc") },
            { kind = "path", value = in_mason("tsc") },
            { kind = "which", value = "tsc" },
        },
        vitest = {
            { kind = "path", value = in_node_modules("vitest") },
            { kind = "which", value = "vitest" },
        },
        jest = {
            { kind = "path", value = in_node_modules("jest") },
            { kind = "which", value = "jest" },
        },
    },

    --- `<bin> --version` — first NON-EMPTY line, trimmed (node / vtsls / prettier / tsc use `--version`).
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
