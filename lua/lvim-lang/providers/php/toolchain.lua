-- lvim-lang.providers.php.toolchain: the PHP toolchain spec.
-- Resolution order for `php` (first executable wins): an explicit `php_path` → a user lookup command
-- → a version manager (mise / asdf honouring the project's pinned PHP) → PATH. `composer` is the
-- user's own dependency manager (explicit `composer_path` → PATH). The language server
-- (`intelephense` by default, `phpactor` optional), `php-cs-fixer` and `phpstan` are mason-registry
-- binaries: an explicit path → the mason bin directory (where the installer drops them) → PATH.
-- `phpunit` is resolved PROJECT-LOCAL first (`vendor/bin/phpunit`, where Composer installs it) →
-- explicit path → PATH. Detection only — nothing is installed here (missing mason tools come from the
-- mason registry via the installer / core.ensure).
--
---@module "lvim-lang.providers.php.toolchain"

local config = require("lvim-lang.config")

--- The php config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.php or {}
end

--- Run the user's `php_lookup_cmd` and take its first non-empty line as the php path.
---@return string|nil
local function lookup_php()
    local cmd = opts().php_lookup_cmd
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

--- Resolve `php` through the configured version manager (mise/asdf), honouring the project's pinned
--- PHP for `root`. `version_manager` may be a manager name ("mise"|"asdf"), false to disable, or a
--- function(root) -> path|nil for a custom seam. Default: try mise then asdf.
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
    -- `<mgr> which php` prints the resolved binary for the directory's pinned toolchain.
    local managers = type(vm) == "string" and { vm } or { "mise", "asdf" }
    for _, mgr in ipairs(managers) do
        if vim.fn.executable(mgr) == 1 then
            local out = vim.system({ mgr, "which", "php" }, { cwd = root, text = true }):wait()
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

--- Build a resolver that returns an explicit config path for `key` (e.g. "php_path"), or nil.
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

--- Build a resolver for a Composer project-local binary `bin` under `<root>/vendor/bin/<bin>` — where
--- Composer installs a project's dev tools (phpunit, php-cs-fixer, phpstan pinned per project). The
--- project's own version wins over any global install, matching how a PHP project is actually run.
---@param bin string
---@return fun(root: string): string|nil
local function in_vendor(bin)
    return function(root)
        if type(root) ~= "string" or root == "" then
            return nil
        end
        local path = vim.fs.joinpath(root, "vendor", "bin", bin)
        return vim.fn.executable(path) == 1 and path or nil
    end
end

---@type LvimLangToolchainSpec
return {
    tools = {
        php = {
            { kind = "path", value = explicit("php_path") },
            { kind = "path", value = lookup_php },
            { kind = "path", value = via_version_manager },
            { kind = "which", value = "php" },
        },
        composer = {
            { kind = "path", value = explicit("composer_path") },
            { kind = "which", value = "composer" },
        },
        intelephense = {
            { kind = "path", value = explicit("intelephense_path") },
            { kind = "path", value = in_mason("intelephense") },
            { kind = "which", value = "intelephense" },
        },
        -- phpactor language server — optional, opt-in (providers.php.lsp.server = "phpactor").
        phpactor = {
            { kind = "path", value = explicit("phpactor_path") },
            { kind = "path", value = in_mason("phpactor") },
            { kind = "which", value = "phpactor" },
        },
        ["php-cs-fixer"] = {
            { kind = "path", value = explicit("php_cs_fixer_path") },
            { kind = "path", value = in_vendor("php-cs-fixer") },
            { kind = "path", value = in_mason("php-cs-fixer") },
            { kind = "which", value = "php-cs-fixer" },
        },
        phpstan = {
            { kind = "path", value = explicit("phpstan_path") },
            { kind = "path", value = in_vendor("phpstan") },
            { kind = "path", value = in_mason("phpstan") },
            { kind = "which", value = "phpstan" },
        },
        -- phpunit is a project dev-dependency (Composer): the project-local `vendor/bin/phpunit`
        -- wins, then an explicit path, then a global PATH install.
        phpunit = {
            { kind = "path", value = explicit("phpunit_path") },
            { kind = "path", value = in_vendor("phpunit") },
            { kind = "which", value = "phpunit" },
        },
    },

    --- `<bin> --version` — first NON-EMPTY line, trimmed. php / composer / intelephense / php-cs-fixer
    --- / phpstan / phpunit all report their version with `--version`.
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
