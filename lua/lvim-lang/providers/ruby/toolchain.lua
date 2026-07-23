-- lvim-lang.providers.ruby.toolchain: the Ruby toolchain spec.
-- Ruby installs are almost always managed by a version manager, and the project's `.ruby-version`
-- pins which one. Resolution order for `ruby` (first executable wins): an explicit `ruby_path` → a
-- user lookup command → the version manager (rbenv / rvm / chruby / asdf / mise, honouring the
-- project pin for `root`) → PATH. The gem-provided tools (`bundle`, `rubocop`, `ruby-lsp`, `rspec`,
-- `rake`, `rdbg`) resolve from the SAME environment first — a project binstub (`bin/<tool>`), then
-- the selected ruby's bin dir (where `gem install` drops executables), then the mason bin, then PATH
-- — so a project-local tool wins over the shared one. Detection only; nothing is installed here.
--
---@module "lvim-lang.providers.ruby.toolchain"

local config = require("lvim-lang.config")

--- The ruby config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.ruby or {}
end

--- Run the user's `ruby_lookup_cmd` and take its first non-empty line as the ruby path.
---@return string|nil
local function lookup_ruby()
    local cmd = opts().ruby_lookup_cmd
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

--- The `<name>` from the project's `.ruby-version` (e.g. "3.3.4" / "ruby-3.3.4"), trimmed, or nil.
---@param root string
---@return string|nil
local function pinned_version(root)
    local path = vim.fs.joinpath(root, ".ruby-version")
    if vim.fn.filereadable(path) ~= 1 then
        return nil
    end
    local lines = vim.fn.readfile(path)
    for _, line in ipairs(lines or {}) do
        local trimmed = vim.trim(line)
        if trimmed ~= "" then
            return trimmed
        end
    end
    return nil
end

--- chruby / rvm have no resolver CLI (chruby is a shell function; rvm's `rvm` is one too), so the
--- selected ruby is found on disk: read the project's `.ruby-version` and look for a matching
--- `<rubies>/<name>/bin/ruby` under the standard install roots (`~/.rubies`, `~/.rvm/rubies`). The
--- pin may be bare ("3.3.4") or prefixed ("ruby-3.3.4"), so both spellings are probed.
---@param root string
---@return string|nil
local function via_rubies_dir(root)
    local ver = pinned_version(root)
    if not ver then
        return nil
    end
    local home = vim.env.HOME or vim.uv.os_homedir()
    if not home then
        return nil
    end
    local names = { ver }
    if not ver:match("^ruby%-") then
        names[#names + 1] = "ruby-" .. ver
    end
    local roots = { vim.fs.joinpath(home, ".rubies"), vim.fs.joinpath(home, ".rvm", "rubies") }
    for _, r in ipairs(roots) do
        for _, name in ipairs(names) do
            local path = vim.fs.joinpath(r, name, "bin", "ruby")
            if vim.fn.executable(path) == 1 then
                return path
            end
        end
    end
    return nil
end

--- Resolve `ruby` through the configured version manager, honouring the project's pin for `root`.
--- `version_manager` may be a manager name ("mise"|"asdf"|"rbenv"|"chruby"|"rvm"), false to disable,
--- or a function(root) -> path|nil. Default: try mise, asdf, rbenv (each `<mgr> which ruby`, run in
--- `root` so `.ruby-version` / `.tool-versions` wins), then chruby / rvm via their rubies dir.
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
    local managers = type(vm) == "string" and { vm } or { "mise", "asdf", "rbenv", "chruby", "rvm" }
    for _, mgr in ipairs(managers) do
        if mgr == "chruby" or mgr == "rvm" then
            local path = via_rubies_dir(root)
            if path then
                return path
            end
        elseif vim.fn.executable(mgr) == 1 then
            -- `<mgr> which ruby` prints the binary for the directory's pinned toolchain.
            local out = vim.system({ mgr, "which", "ruby" }, { cwd = root, text = true }):wait()
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

--- Build a resolver that returns the explicit config path under `key` (e.g. "ruby_path"), or nil.
---@param key string
---@return fun(): string|nil
local function explicit(key)
    return function()
        return opts()[key]
    end
end

--- Resolve a gem tool `bin` from the project's binstub directory: `<root>/bin/<bin>`, if executable.
--- A project that ran `bundle binstubs` (or ships `bin/rubocop`, `bin/rspec`) is preferred.
---@param bin string
---@return fun(root: string): string|nil
local function in_binstub(bin)
    return function(root)
        local path = vim.fs.joinpath(root, "bin", bin)
        return vim.fn.executable(path) == 1 and path or nil
    end
end

--- Resolve a gem tool `bin` inside the selected ruby's bin directory (where `gem install` drops
--- executables): `<dirname(ruby)>/<bin>`, if executable. Tracks a version-managed ruby's own gems.
---@param bin string
---@return fun(root: string): string|nil
local function in_ruby_bin(bin)
    return function(root)
        local ruby = require("lvim-lang.core.toolchain").resolve("ruby", "ruby", root)
        if not ruby then
            return nil
        end
        local path = vim.fs.joinpath(vim.fs.dirname(ruby), bin)
        return vim.fn.executable(path) == 1 and path or nil
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
        -- The interpreter: config → lookup cmd → version manager (project pin) → PATH.
        ruby = {
            { kind = "path", value = explicit("ruby_path") },
            { kind = "path", value = lookup_ruby },
            { kind = "path", value = via_version_manager },
            { kind = "which", value = "ruby" },
        },
        -- Bundler ships with ruby: the selected ruby's bin dir → PATH.
        bundle = {
            { kind = "path", value = explicit("bundle_path") },
            { kind = "path", value = in_ruby_bin("bundle") },
            { kind = "which", value = "bundle" },
        },
        -- rubocop is a gem (also a mason package): config → binstub → ruby bin → mason → PATH.
        rubocop = {
            { kind = "path", value = explicit("rubocop_path") },
            { kind = "path", value = in_binstub("rubocop") },
            { kind = "path", value = in_ruby_bin("rubocop") },
            { kind = "path", value = in_mason("rubocop") },
            { kind = "which", value = "rubocop" },
        },
        -- The ruby-lsp language server (a gem, also a mason package): config → binstub → ruby bin →
        -- mason → PATH.
        ["ruby-lsp"] = {
            { kind = "path", value = explicit("ruby_lsp_path") },
            { kind = "path", value = in_binstub("ruby-lsp") },
            { kind = "path", value = in_ruby_bin("ruby-lsp") },
            { kind = "path", value = in_mason("ruby-lsp") },
            { kind = "which", value = "ruby-lsp" },
        },
        -- solargraph (the alternative server, a gem — also a mason package).
        solargraph = {
            { kind = "path", value = in_binstub("solargraph") },
            { kind = "path", value = in_ruby_bin("solargraph") },
            { kind = "path", value = in_mason("solargraph") },
            { kind = "which", value = "solargraph" },
        },
        -- RSpec (a gem): a project binstub → the selected ruby's bin → PATH. Normally run via
        -- `bundle exec rspec` (see providers.ruby.test), so this is the fallback direct binary.
        rspec = {
            { kind = "path", value = in_binstub("rspec") },
            { kind = "path", value = in_ruby_bin("rspec") },
            { kind = "which", value = "rspec" },
        },
        -- rake ships with ruby: the selected ruby's bin → PATH.
        rake = {
            { kind = "path", value = in_binstub("rake") },
            { kind = "path", value = in_ruby_bin("rake") },
            { kind = "which", value = "rake" },
        },
        -- rdbg — the `debug` gem's remote debugger (NOT a mason package; `bundle add debug`):
        -- config → binstub → the selected ruby's bin → PATH.
        rdbg = {
            { kind = "path", value = explicit("rdbg_path") },
            { kind = "path", value = in_binstub("rdbg") },
            { kind = "path", value = in_ruby_bin("rdbg") },
            { kind = "which", value = "rdbg" },
        },
    },

    --- `<bin> --version` — first NON-EMPTY line, trimmed (ruby / bundle / rubocop / ruby-lsp / rspec
    --- / rake / rdbg all accept `--version`).
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
