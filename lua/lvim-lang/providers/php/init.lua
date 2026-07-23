-- lvim-lang.providers.php: the PHP provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Reuses the shared core: the per-filetype
-- catalog (core.catalog), the LSP fan-out (core.lsp.register_catalog), the lvim-tasks runner
-- (core.runner) and on-demand tooling (core.ensure).
--
-- LSP: intelephense is the DEFAULT — a plain stdio LSP (mason `intelephense`, launched
-- `intelephense --stdio`) that formats + diagnoses PHP natively. phpactor is included in the catalog
-- as an OPT-IN alternative (mason `phpactor`, launched `phpactor language-server`); select it via
-- `providers.php.lsp.server = "phpactor"` (its server-config module is servers/phpactor.lua). Matching
-- the sibling providers (java/csharp/python/cpp) whose language server formats + diagnoses natively,
-- the per-filetype efm formatter / linter DEFAULT to `false`; the catalog still OFFERS php-cs-fixer
-- (formatter) and phpstan (linter) over efm for users who prefer them — selecting php-cs-fixer
-- auto-disables intelephense's own formatting (core.catalog.lsp_on_attach) so the buffer is not
-- double-formatted. Project-wide phpstan / php-cs-fixer are also available as one-shot tasks
-- (`:LvimLang analyse` / `:LvimLang cs-fix`).
--
-- Debugging is Xdebug via php-debug-adapter (a CONNECTION-driven adapter — it listens for the PHP
-- runtime to connect); see providers.php.dap. Dependency management is Composer (providers.php.deps).
--
---@module "lvim-lang.providers.php"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.providers.php.toolchain")
local core_toolchain = require("lvim-lang.core.toolchain")
local requirements = require("lvim-lang.core.requirements")

-- Per-language defaults, merged into config.providers.php at registration (users override via
-- setup({ providers = { php = { … } } })).
---@type table
local DEFAULTS = {
    -- Explicit binary paths; when set each wins over every other resolution strategy.
    php_path = nil,
    composer_path = nil,
    intelephense_path = nil,
    phpactor_path = nil,
    php_cs_fixer_path = nil,
    phpstan_path = nil,
    phpunit_path = nil,
    php_debug_adapter_path = nil,
    -- A shell command whose first output line is the `php` binary path (checked after php_path,
    -- before the version manager / PATH). Empty by default.
    php_lookup_cmd = nil,
    -- Version manager for `php`: "mise" | "asdf" | false (ignore) | function(root). Honours the
    -- project's pinned PHP. Default: try mise then asdf, else PATH.
    version_manager = nil,

    -- Debugging: the port php-debug-adapter LISTENS on for an Xdebug connection (Xdebug 3 default).
    debug_port = 9003,

    -- `:LvimLang serve` — the built-in development web server target (all overridable).
    serve_host = "localhost",
    serve_port = 8000,
    serve_docroot = nil, -- `-t <docroot>`; nil = the project root

    -- intelephense premium: a licence key + on-disk index storage path (both optional). nil storage
    -- → intelephense's own default under stdpath("cache").
    licence_key = nil,
    storage_path = nil,

    -- LSP server catalog. intelephense is the default (a stdio LSP that formats + diagnoses natively).
    -- phpactor is an opt-in alternative (see servers/phpactor.lua). `default` may be a STRING or a
    -- LIST (several LSP clients attach to the same buffer).
    lsp = {
        servers = {
            intelephense = {
                mason = "intelephense",
                bin = "intelephense",
                filetypes = { "php" },
                role = "types", -- completion / hover / definition / rename / format / diagnostics
                settings = {
                    intelephense = {
                        files = { maxSize = 5000000 },
                        completion = {
                            fullyQualifyGlobalConstantsAndFunctions = false,
                            insertUseDeclaration = true,
                        },
                        diagnostics = { enable = true },
                        format = { enable = true },
                    },
                },
            },
            phpactor = {
                mason = "phpactor",
                bin = "phpactor",
                filetypes = { "php" },
                role = "types",
                settings = {},
            },
        },
        default = "intelephense", -- string | string[]; set to "phpactor" to use phpactor instead
    },

    -- Per-FILETYPE catalog: formatters / linters / debuggers available for `php`, each with a default
    -- configuration, plus which one is the `default` (or false = none). Only the CHOSEN tools are
    -- installed (their mason package is contributed to the installer) and wired (through
    -- efm-langserver). Every entry is fully overridable via
    -- setup({ providers = { php = { ft = { php = { formatter = "php-cs-fixer" } } } } }).
    ft = {
        php = {
            formatters = {
                -- php-cs-fixer has no stdin→stdout mode: efm writes the buffer to the ${INPUT} temp
                -- file, php-cs-fixer rewrites it in place (cache off, quiet), then `cat` emits the
                -- result as efm's replacement text. Opt-in (intelephense formats by default); when
                -- chosen, intelephense's own formatting is switched off (catalog.lsp_on_attach). A
                -- project `.php-cs-fixer.php` is auto-detected; without one, tune the rules here.
                ["php-cs-fixer"] = {
                    mason = "php-cs-fixer",
                    efm = {
                        formatCommand = "php-cs-fixer fix --using-cache=no --quiet ${INPUT}; cat ${INPUT}",
                        formatStdin = false,
                    },
                },
            },
            linters = {
                -- phpstan over efm: analyses the ${INPUT} file, reads the project's phpstan.neon for
                -- its level / autoload (gated by rootMarkers so it only runs where configured). Opt-in
                -- (intelephense diagnoses by default). `raw` error format = `path:line:message`.
                phpstan = {
                    mason = "phpstan",
                    efm = {
                        lintCommand = "phpstan analyse --error-format=raw --no-progress --no-ansi ${INPUT}",
                        lintStdin = false,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%f:%l:%m" },
                        rootMarkers = { "phpstan.neon", "phpstan.neon.dist", "phpstan.dist.neon" },
                    },
                },
            },
            debuggers = {
                -- php-debug-adapter: no bundle — a standalone DAP adapter for Xdebug. Selecting it
                -- installs the mason package; the adapter/configurations are in providers.php.dap.
                ["php-debug-adapter"] = { mason = "php-debug-adapter" },
            },
            -- intelephense formats + diagnoses PHP natively, so no default efm formatter / linter (the
            -- sibling canon). The catalog still OFFERS php-cs-fixer / phpstan (set ft.php.formatter =
            -- "php-cs-fixer" / ft.php.linter = "phpstan").
            defaults = { formatter = false, linter = false, debugger = "php-debug-adapter" },
        },
    },

    -- Nerd Font icons used in the PHP provider's statusline / pickers (all configurable).
    icons = {
        statusline = "󰌟", -- the PHP marker in the statusline segment
        test = "󰙨", -- test runner / result row
        build = "󰜫", -- build task row
        run = "󰐊", -- run task row
        debug = "󰃤", -- debug session row
        deps = "󰏗", -- Composer dependency row
    },
}

--- Health section for :checkhealth lvim-lang: whether the PHP runtime + Composer resolve for the
--- current working directory, and at what version, plus the chosen language server.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."

    local php, reason = core_toolchain.resolve("php", "php", root)
    if php then
        local ver = core_toolchain.version("php", "php", root)
        h.ok(("php: %s%s"):format(php, ver and ("  (" .. ver .. ")") or ""))
    else
        h.warn(
            ("php not found — %s"):format(
                reason or "install PHP and put `php` on PATH, or set providers.php.php_path"
            )
        )
    end

    local composer = core_toolchain.resolve("php", "composer", root)
    if composer then
        h.ok(("composer: %s"):format(composer))
    else
        h.info("composer not found — install Composer for dependency commands")
    end

    -- Report the CHOSEN language server binary (intelephense by default; phpactor otherwise).
    local lsp = (config.providers.php and config.providers.php.lsp) or {}
    local server = lsp.server or lsp.default or "intelephense"
    if type(server) == "table" then
        server = server[1]
    end
    local server_path = core_toolchain.resolve("php", server, root)
    if server_path then
        h.ok(("%s: %s"):format(server, server_path))
    else
        h.info(("%s not found — installed on demand from the mason registry"):format(server))
    end
end

--- Statusline segment for a root: the PHP marker + the active run config (if any).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.php and config.providers.php.icons) or {}
    local parts = { ic.statusline or "󰌟" }
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
    name = "php",
    filetypes = { "php" },
    root_patterns = { "composer.json", ".git" },
    statusline = statusline,
    toolchain = toolchain,
    commands = require("lvim-lang.providers.php.commands"),
    -- lvim-tasks templates (arg-less Composer subcommands) — also runnable via :LvimLang deps.
    tasks = require("lvim-lang.providers.php.deps").templates,
    --- Surfaced at activation + in :checkhealth: the PHP runtime must be present (the server, tests
    --- and every task invoke it; php-debug-adapter needs Xdebug in that runtime).
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
        return {
            requirements.tool_present(
                "php",
                "php",
                "PHP runtime",
                "Install PHP and put `php` on PATH (or set providers.php.php_path); the language server, "
                    .. "tests and tasks all invoke it. For debugging, enable Xdebug in that runtime.",
                root
            ),
        }
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
