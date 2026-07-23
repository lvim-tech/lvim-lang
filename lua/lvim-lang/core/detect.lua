-- lvim-lang.core.detect: reusable toolchain-resolution strategy builders, shared by every provider.
-- The bespoke providers (zig, rust, …) each hand-rolled the SAME four strategies — an explicit config
-- path, a mason-bin lookup, a version-manager query, a PATH lookup. This module factors them into one
-- set of builders so the declarative factory (core.declarative) synthesises a LvimLangToolchainSpec from
-- data, AND any bespoke provider can drop its own copies and reuse these (the base+extend model). Every
-- builder returns a `value` resolver for a LvimLangToolchainStrategy (see core.toolchain). Detection
-- only — nothing is installed here; installation is lvim-pkg's job.
--
---@module "lvim-lang.core.detect"

local config = require("lvim-lang.config")

local M = {}

--- The provider's live option block (defaults seeded at register, user overrides merged in).
---@param name string
---@return table
local function popts(name)
    return config.providers[name] or {}
end

--- An explicit user override for `tool` from config.providers[name].bin_paths[tool], or nil. Wins over
--- every other strategy so a user can always pin a binary.
---@param name string
---@param tool string
---@return fun(): string|nil
function M.explicit(name, tool)
    return function()
        local paths = popts(name).bin_paths or {}
        return paths[tool]
    end
end

--- `bin` inside the mason bin dir (where lvim-installer drops tools), if executable — else nil. The
--- mason path is owned by lvim-pkg; this never assumes a hard-coded location.
---@param bin string
---@return fun(): string|nil
function M.in_mason(bin)
    return function()
        local ok, pkg = pcall(require, "lvim-pkg")
        if not ok or type(pkg.bin_dir) ~= "function" then
            return nil
        end
        local path = vim.fs.joinpath(pkg.bin_dir(), bin)
        return vim.fn.executable(path) == 1 and path or nil
    end
end

--- Run the config command at `config.providers[name][opt_key]` and take its first non-empty output
--- line as a binary path (the seam for managers that PRINT a resolved path — swiftly, a custom shim).
--- Empty / unset key → nil. Factored from the per-provider lookup helpers that every SDK provider had.
---@param name string
---@param opt_key string
---@return fun(): string|nil
function M.lookup(name, opt_key)
    return function()
        local cmd = popts(name)[opt_key]
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
end

--- SDKMAN keeps the selected candidate at `$SDKMAN_DIR/candidates/<candidate>/current/bin/<bin>` (the
--- `sdk` command itself is a shell function, not an executable, so the symlinked `current` is read).
--- The common Kotlin / Java / Gradle / Scala manager. nil when SDKMAN is absent or the bin is not there.
---@param candidate string  SDKMAN candidate name (java / kotlin / gradle / scala / …)
---@param bin string
---@return string|nil
function M.via_sdkman(candidate, bin)
    local dir = vim.env.SDKMAN_DIR
    if not dir or dir == "" then
        return nil
    end
    local path = vim.fs.joinpath(dir, "candidates", candidate, "current", "bin", bin)
    return vim.fn.executable(path) == 1 and path or nil
end

--- Resolve `bin` through the provider's configured version manager, honouring the project's pinned
--- version for `root`. config.providers[name].version_manager may be a manager name, false to disable,
--- or a function(root, bin) -> path|nil for a custom seam. When it is not set, the candidate list is
--- `opts.managers` (e.g. { "rustup", "mise", "asdf" }), else the default mise → asdf → SDKMAN. Every
--- named manager except SDKMAN is queried `<mgr> which <bin>` (rustup / rbenv / mise / asdf all share
--- that verb); SDKMAN uses its candidate layout. Run in `root` so a project pin wins over a global one.
---@param name string
---@param bin string
---@param opts? { sdkman?: string, managers?: string[] }  sdkman = SDKMAN candidate; managers = the default candidate list
---@return fun(root: string): string|nil
function M.via_version_manager(name, bin, opts)
    opts = opts or {}
    return function(root)
        local vm = popts(name).version_manager
        if vm == false then
            return nil
        end
        if type(vm) == "function" then
            return vm(root, bin)
        end
        local managers = type(vm) == "string" and { vm } or opts.managers or { "mise", "asdf", "sdkman" }
        for _, mgr in ipairs(managers) do
            if mgr == "sdkman" then
                if opts.sdkman then
                    local path = M.via_sdkman(opts.sdkman, bin)
                    if path then
                        return path
                    end
                end
            elseif vim.fn.executable(mgr) == 1 then
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
end

--- `bin` inside a project-local bin dir `<root>/<dir>/<bin>` (Composer `vendor/bin`, node
--- `node_modules/.bin`, a Ruby binstub `bin`, a Python `.venv/bin`), if executable — else nil. The
--- project's own pinned tool wins over a global install, matching how the project is actually run.
---@param dir string   project-relative bin dir (e.g. "vendor/bin")
---@param bin string
---@return fun(root: string): string|nil
function M.in_project(dir, bin)
    return function(root)
        if type(root) ~= "string" or root == "" then
            return nil
        end
        local path = vim.fs.joinpath(root, dir, bin)
        return vim.fn.executable(path) == 1 and path or nil
    end
end

--- Ordered strategies for a MASON tool (an LSP server / formatter / linter / debugger installed by
--- lvim-installer): explicit override → each project-local bin dir → the mason bin dir → PATH. `tool`
--- is the toolchain key; `bin` the executable name (defaults to the key). `project_dirs` (optional) are
--- project-relative bin dirs probed before mason, so a project-pinned copy wins (harmless for tools not
--- installed there — the check just falls through).
---@param name string
---@param tool string
---@param bin? string
---@param project_dirs? string[]
---@return LvimLangToolchainStrategy[]
function M.mason_strategies(name, tool, bin, project_dirs)
    bin = bin or tool
    local strategies = { { kind = "path", value = M.explicit(name, tool) } }
    for _, dir in ipairs(project_dirs or {}) do
        strategies[#strategies + 1] = { kind = "path", value = M.in_project(dir, bin) }
    end
    strategies[#strategies + 1] = { kind = "path", value = M.in_mason(bin) }
    strategies[#strategies + 1] = { kind = "which", value = bin }
    return strategies
end

--- Ordered strategies for a SYSTEM runtime / compiler the user owns (node, go, kotlinc, …): explicit
--- override → an optional LOOKUP command → the project's version manager (mise/asdf/SDKMAN) → PATH.
--- lvim-pkg does NOT install these; they are resolved, and their absence is surfaced as a requirement
--- rather than silently failing. `opts.lookup_key` (a config key holding a lookup command) and
--- `opts.sdkman` (the SDKMAN candidate) are the two data-declared seams the SDK providers need.
---@param name string
---@param tool string
---@param bin? string
---@param opts? { lookup_key?: string, sdkman?: string, managers?: string[] }
---@return LvimLangToolchainStrategy[]
function M.runtime_strategies(name, tool, bin, opts)
    bin = bin or tool
    opts = opts or {}
    local strategies = { { kind = "path", value = M.explicit(name, tool) } }
    if opts.lookup_key then
        strategies[#strategies + 1] = { kind = "path", value = M.lookup(name, opts.lookup_key) }
    end
    strategies[#strategies + 1] = {
        kind = "path",
        value = M.via_version_manager(name, bin, { sdkman = opts.sdkman, managers = opts.managers }),
    }
    strategies[#strategies + 1] = { kind = "which", value = bin }
    return strategies
end

--- A generic version prober: the first non-empty line of `<bin> --version` (trimmed), or nil. Providers
--- whose tools answer version differently (Zig's `zig version` subcommand) override toolchain.version.
---@param bin string
---@return string|nil
function M.version(bin)
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
end

--- A version prober reading BOTH streams of `<bin> <flag>` (JVM tools — java / kotlinc / scala — print
--- their banner to stderr with `-version`). Returns the first non-empty line, trimmed, or nil.
---@param flag? string  version flag (default "--version")
---@return fun(bin: string): string|nil
function M.version_both(flag)
    flag = flag or "--version"
    return function(bin)
        local res = vim.system({ bin, flag }, { text = true }):wait()
        local text = (res.stderr or "") .. "\n" .. (res.stdout or "")
        for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
            local trimmed = vim.trim(line)
            if trimmed ~= "" then
                return trimmed
            end
        end
        return nil
    end
end

return M
