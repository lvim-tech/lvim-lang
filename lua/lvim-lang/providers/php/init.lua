-- lvim-lang.providers.php: the PHP provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes/root, the intelephense (default) + phpactor (opt-in) LSP catalog, the per-filetype
-- tool catalog (php-cs-fixer / phpstan / php-debug-adapter), the php + composer toolchain, requirements,
-- health and statusline. `project_dirs = { "vendor/bin" }` makes every mason tool prefer a Composer
-- project-local copy. This module then EXTENDS the returned spec with PHP's idiosyncratic parts:
--   * phpunit resolution (the project's vendor/bin/phpunit, not a mason package);
--   * the extra provider config (Xdebug port, the built-in web server target, the intelephense premium
--     licence / storage) seeded onto the defaults;
--   * the one-shot task / Composer / Xdebug command surface (providers.php.commands / .dap / .deps).
--
-- The reusable strategy builders (explicit / lookup / version-manager / project-local / mason / PATH)
-- come from core.detect via the factory. intelephense / phpactor keep their bespoke server-config
-- modules (servers/intelephense.lua, servers/phpactor.lua — a real file wins over the generic shim).
--
---@module "lvim-lang.providers.php"

local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")
local detect = require("lvim-lang.core.detect")

-- Explicit binary overrides live under `bin_paths` (the shared key); `php_lookup_cmd` holds an optional
-- path-printing lookup command; the debug / serve / intelephense-premium keys are seeded in the extend.
---@type LvimLangSpecData
local DATA = {
    name = "php",
    filetypes = { "php" },
    root_patterns = { "composer.json", ".git" },

    -- php is the user's own runtime (required); composer their dependency manager (resolved, not surfaced).
    runtimes = {
        {
            bin = "php",
            key = "php",
            lookup_key = "php_lookup_cmd",
            require = true,
            label = "PHP runtime",
            hint = "Install PHP and put `php` on PATH (or set providers.php.bin_paths.php); the language server, "
                .. "tests and tasks all invoke it. For debugging, enable Xdebug in that runtime.",
        },
        { bin = "composer", key = "composer" },
    },

    -- Composer installs a project's dev tools under vendor/bin — prefer them over a global/mason copy.
    project_dirs = { "vendor/bin" },

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

    ft = {
        php = {
            formatters = {
                ["php-cs-fixer"] = {
                    mason = "php-cs-fixer",
                    efm = {
                        formatCommand = "php-cs-fixer fix --using-cache=no --quiet ${INPUT}; cat ${INPUT}",
                        formatStdin = false,
                    },
                },
                pint = {
                    mason = "pint",
                    efm = { formatCommand = "pint --quiet ${INPUT}; cat ${INPUT}", formatStdin = false },
                },
                ["pretty-php"] = { mason = "pretty-php", efm = { formatCommand = "pretty-php -", formatStdin = true } },
                phpcbf = {
                    mason = "phpcbf",
                    efm = { formatCommand = "phpcbf -q -", formatStdin = true },
                },
                ["easy-coding-standard"] = {
                    mason = "easy-coding-standard",
                    bin = "ecs",
                    efm = {
                        formatCommand = "ecs check --fix --no-progress-bar --no-interaction ${INPUT}; cat ${INPUT}",
                        formatStdin = false,
                    },
                },
                duster = {
                    mason = "duster",
                    efm = { formatCommand = "duster fix ${INPUT}; cat ${INPUT}", formatStdin = false },
                },
            },
            linters = {
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
                phpcs = {
                    mason = "phpcs",
                    efm = {
                        lintCommand = "phpcs --report=emacs -q --stdin-path=${INPUT} -",
                        lintStdin = true,
                        lintFormats = { "%f:%l:%c: %trror - %m", "%f:%l:%c: %tarning - %m" },
                    },
                },
                phpmd = {
                    mason = "phpmd",
                    efm = {
                        lintCommand = "phpmd ${INPUT} text cleancode,codesize,controversial,design,naming,unusedcode",
                        lintStdin = false,
                        lintFormats = { "%f:%l%*[	 ]%m" },
                    },
                },
                tlint = {
                    mason = "tlint",
                    efm = {
                        lintCommand = "tlint lint ${INPUT}",
                        lintStdin = false,
                        lintFormats = { "%f:%l:%c: %m", "%f:%l %m" },
                    },
                },
                semgrep = {
                    mason = "semgrep",
                    efm = {
                        lintCommand = "semgrep scan --config auto --quiet --error --disable-version-check --gitlab-sast ${INPUT}",
                        lintStdin = false,
                        lintFormats = { "%f:%l:%c: %m" },
                    },
                },
            },
            debuggers = {
                ["php-debug-adapter"] = { mason = "php-debug-adapter" },
            },
            -- intelephense formats + diagnoses natively → no default efm formatter / linter; the catalog
            -- still OFFERS php-cs-fixer / phpstan (set ft.php.formatter/linter).
            defaults = { formatter = false, linter = false, debugger = "php-debug-adapter" },
        },
    },

    icons = {
        statusline = "󰌟", -- the PHP marker in the statusline segment
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗", -- Composer dependency row
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND ─────────────────────────────────────────────────────────────────────────────────────────

-- phpunit is a project dev-dependency (Composer): the project-local vendor/bin/phpunit wins, then an
-- explicit path, then a global PATH install. Not a mason package, so it is added here (not in the union).
spec.toolchain.tools.phpunit = {
    { kind = "path", value = detect.explicit("php", "phpunit") },
    { kind = "path", value = detect.in_project("vendor/bin", "phpunit") },
    { kind = "which", value = "phpunit" },
}

-- Extra provider config the commands / dap / server read.
defaults.debug_port = 9003 -- the port php-debug-adapter LISTENS on for an Xdebug connection (Xdebug 3)
defaults.serve_host = "localhost" -- `:LvimLang serve` — the built-in development web server target
defaults.serve_port = 8000
defaults.serve_docroot = nil -- `-t <docroot>`; nil = the project root
defaults.licence_key = nil -- intelephense premium licence key (optional)
defaults.storage_path = nil -- intelephense on-disk index storage path (nil = its own default)

-- The one-shot task / Composer / Xdebug command surface + arg-less Composer templates.
spec.commands = require("lvim-lang.providers.php.commands")
spec.tasks = require("lvim-lang.providers.php.deps").templates

registry.register(spec, defaults)

return spec
