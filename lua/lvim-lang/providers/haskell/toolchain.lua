-- lvim-lang.providers.haskell.toolchain: the Haskell toolchain spec.
-- Haskell toolchains are the user's OWN, installed and switched almost universally through GHCup
-- (which also surfaces cabal / stack / hls), and often through mise / asdf. Resolution order for each
-- tool (first executable wins): an explicit config path → a user lookup command → the version manager
-- (`ghcup whereis <component>`, which honours the active GHCup set; then `mise`/`asdf which`) → the
-- GHCup bin dir (`~/.ghcup/bin`) → PATH. haskell-language-server additionally falls back to the mason
-- bin (the `haskell-language-server-wrapper`, a github release). Detection only — nothing is installed.
--
---@module "lvim-lang.providers.haskell.toolchain"

local config = require("lvim-lang.config")

--- The haskell config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.haskell or {}
end

--- Run the user's `ghc_lookup_cmd` and take its first non-empty line as the ghc path.
---@return string|nil
local function lookup_ghc()
    local cmd = opts().ghc_lookup_cmd
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

-- The GHCup component name for each toolchain tool (`ghcup whereis <component>`). Tools NOT managed
-- by GHCup (the formatters / linter / debug adapter) are absent here and skip the version-manager step.
---@type table<string, string>
local GHCUP_COMPONENT = {
    ghc = "ghc",
    cabal = "cabal",
    stack = "stack",
    ["haskell-language-server"] = "hls",
}

--- Resolve `tool` through the configured version manager, honouring the active toolchain for `root`.
--- `version_manager` may be a manager name ("ghcup"|"mise"|"asdf"), false to disable, or a
--- function(root, tool) -> path|nil. Default: try ghcup (`ghcup whereis <component>`) then mise/asdf.
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
    local managers = type(vm) == "string" and { vm } or { "ghcup", "mise", "asdf" }
    for _, mgr in ipairs(managers) do
        if vim.fn.executable(mgr) == 1 then
            local argv
            if mgr == "ghcup" then
                -- `ghcup whereis <component>` prints the active set's binary; only ghcup-managed
                -- components have one (ghc / cabal / stack / hls). Others fall through to the next step.
                local component = GHCUP_COMPONENT[tool]
                argv = component and { mgr, "whereis", component } or nil
            else
                -- `mise/asdf which <tool>` prints the directory's pinned binary.
                argv = { mgr, "which", tool }
            end
            if argv then
                local out = vim.system(argv, { cwd = root, text = true }):wait()
                if out.code == 0 then
                    local path = vim.trim(out.stdout or "")
                    if path ~= "" and vim.fn.executable(path) == 1 then
                        return path
                    end
                end
            end
        end
    end
    return nil
end

--- The tool inside the GHCup bin dir (`$GHCUP_BIN` or `~/.ghcup/bin`), if executable there. `bin` is
--- the on-disk binary name (differs from the tool key for haskell-language-server → its wrapper).
---@param bin string
---@return string|nil
local function in_ghcup_bin(bin)
    local dir = vim.env.GHCUP_BIN
    if not dir or dir == "" then
        dir = vim.fs.joinpath(vim.env.HOME or vim.fn.expand("~"), ".ghcup", "bin")
    end
    local path = vim.fs.joinpath(dir, bin)
    return vim.fn.executable(path) == 1 and path or nil
end

--- The haskell-language-server-wrapper binary inside the resolved mason bin dir, if installed there
--- (the mason `haskell-language-server` package installs the wrapper, which selects the right HLS for
--- the project's GHC).
---@return string|nil
local function hls_in_mason()
    local ok, pkg = pcall(require, "lvim-pkg")
    if not ok or type(pkg.bin_dir) ~= "function" then
        return nil
    end
    local path = vim.fs.joinpath(pkg.bin_dir(), "haskell-language-server-wrapper")
    return vim.fn.executable(path) == 1 and path or nil
end

--- Build a resolver that returns an explicit config path for `key` (e.g. "ghc_path"), or nil.
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

--- Build a GHCup-bin resolver for on-disk binary `bin`.
---@param bin string
---@return fun(): string|nil
local function ghcup(bin)
    return function()
        return in_ghcup_bin(bin)
    end
end

---@type LvimLangToolchainSpec
return {
    tools = {
        ghc = {
            { kind = "path", value = explicit("ghc_path") },
            { kind = "path", value = lookup_ghc },
            { kind = "path", value = vm("ghc") },
            { kind = "path", value = ghcup("ghc") },
            { kind = "which", value = "ghc" },
        },
        cabal = {
            { kind = "path", value = explicit("cabal_path") },
            { kind = "path", value = vm("cabal") },
            { kind = "path", value = ghcup("cabal") },
            { kind = "which", value = "cabal" },
        },
        stack = {
            { kind = "path", value = explicit("stack_path") },
            { kind = "path", value = vm("stack") },
            { kind = "path", value = ghcup("stack") },
            { kind = "which", value = "stack" },
        },
        ["haskell-language-server"] = {
            { kind = "path", value = explicit("hls_path") },
            { kind = "path", value = vm("haskell-language-server") },
            { kind = "path", value = ghcup("haskell-language-server-wrapper") },
            { kind = "path", value = hls_in_mason },
            { kind = "which", value = "haskell-language-server-wrapper" },
            { kind = "which", value = "haskell-language-server" },
        },
        fourmolu = {
            { kind = "path", value = explicit("fourmolu_path") },
            { kind = "which", value = "fourmolu" },
        },
        ormolu = {
            { kind = "path", value = explicit("ormolu_path") },
            { kind = "which", value = "ormolu" },
        },
        hlint = {
            { kind = "path", value = explicit("hlint_path") },
            { kind = "which", value = "hlint" },
        },
        ["haskell-debug-adapter"] = {
            { kind = "path", value = explicit("haskell_debug_adapter_path") },
            { kind = "which", value = "haskell-debug-adapter" },
        },
    },

    --- `<bin> --version` — first NON-EMPTY line, trimmed (every Haskell tool uses `--version`).
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
