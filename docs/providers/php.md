# PHP provider

The PHP provider owns PHP tooling through `lvim-lang`: **intelephense** (LSP, phpactor offered as the
alternative), running the current file / **PHPUnit** tests / **phpstan** analysis / **php-cs-fixer**
style-fixing / the built-in `php -S` web server through **lvim-tasks**, Composer dependency commands,
and **Xdebug** debugging through **php-debug-adapter** + **lvim-dap**. Everything is resolved per
project and lazy — nothing is wired until the first PHP buffer is opened.

Filetypes: `php`. Project root: `composer.json` → `.git`.

## Toolchain

Resolved per project root (explicit path wins over everything):

- **`php`** — explicit `php_path` → `php_lookup_cmd` → version manager (**mise**, then **asdf**, each
  `<mgr> which php` run in the project so a pinned version wins) → PATH. PHP is the user's **own**
  runtime (not lvim-pkg-installed).
- **`composer`** — explicit → PATH.
- **`intelephense`** / **`phpactor`** / **`php-cs-fixer`** / **`phpstan`** — explicit path → project
  `vendor/bin/<tool>` → the mason bin → PATH.
- **`phpunit`** — a project `vendor/bin/phpunit` → PATH (normally run via `composer` / the vendor bin).
- **`php-debug-adapter`** — explicit path → the mason bin.

A missing `php` is surfaced at activation and in `:checkhealth` with an install hint.

## Auto-install (the file-open popup)

Opening a PHP file offers the **active** tools it lacks through the unified `lvim-installer` popup:
intelephense (LSP), php-debug-adapter (the default debugger), and any chosen efm formatter / linter
(php-cs-fixer / phpstan). Xdebug itself must be enabled in the PHP runtime — it is not a mason package.

## LSP server catalog

intelephense is the default; phpactor is offered as the alternative (`lsp.default = "phpactor"`, or a
list of both). intelephense formats + diagnoses PHP natively, so the per-filetype efm formatter /
linter default to `false` (the LSP owns them).

| Server | Role | Filetypes |
| --- | --- | --- |
| `intelephense` (default) | types / hover / definition / rename / format / diagnostics | php |
| `phpactor` | alternative full server | php |

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `php` | php-cs-fixer, pint, pretty-php, phpcbf, easy-coding-standard, duster (efm) | phpstan, phpcs, phpmd, tlint, semgrep (efm) | php-debug-adapter | formatter=false, linter=false, debugger=php-debug-adapter |

Selecting an efm formatter (`ft.php.formatter = "php-cs-fixer"`) makes efm own formatting; intelephense's
formatting is switched off on attach so the two never both format the buffer. phpstan is gated by its
`rootMarkers` (`phpstan.neon*`) so it only runs where the project configures it.

## Commands

`:LvimLang <sub> [args]` in a PHP buffer:

| Command | Description |
| --- | --- |
| `:LvimLang run [args]` | run the current file with `php` (+ the active run config) |
| `:LvimLang test [args]` | PHPUnit — the whole suite |
| `:LvimLang test-file` | run every PHPUnit test in the current file |
| `:LvimLang test-func` | run the PHPUnit method under the cursor (`--filter`) |
| `:LvimLang analyse [args]` | `phpstan analyse` — project-wide static analysis |
| `:LvimLang cs-fix [args]` | `php-cs-fixer fix` — project-wide code-style fixing |
| `:LvimLang serve [args]` | `php -S host:port` — the built-in development web server |
| `:LvimLang require <package[:constraint]>` | `composer require` |
| `:LvimLang remove <package>` | `composer remove` |
| `:LvimLang deps <install\|update\|dump-autoload>` | Composer dependency commands |
| `:LvimLang debug` | start / continue a php-debug-adapter (Xdebug) session |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

## Debugging

Debugging uses **php-debug-adapter**, a standalone DAP adapter that LISTENS for an Xdebug connection on
`debug_port` (9003, the Xdebug 3 default). Enable Xdebug in the PHP runtime and point it at that port
(`xdebug.mode=debug`, `xdebug.client_port=9003`). `:LvimLang debug` starts / continues the session.

## Run configurations

Named configs in `.lvim/lang/run.lua`. `:LvimLang config` picks the active one; `:LvimLang run` applies
its script / args / env.

```lua
return {
    {
        name = "cli",
        script = "bin/console", -- the file to run (default: the current buffer)
        args = { "app:sync" }, -- program arguments
        env = { APP_ENV = "dev" },
    },
    { name = "default" },
}
```

## Configuration

The complete default `providers.php` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        php = {
            -- Toolchain (explicit paths win over resolution).
            php_path = nil,
            composer_path = nil,
            intelephense_path = nil,
            phpactor_path = nil,
            php_cs_fixer_path = nil,
            phpstan_path = nil,
            phpunit_path = nil,
            php_debug_adapter_path = nil,
            php_lookup_cmd = nil, -- shell command whose first line is the `php` path
            version_manager = nil, -- "mise"|"asdf"|false|function(root); default: mise→asdf→PATH

            -- Debugging: the port php-debug-adapter listens on for Xdebug (Xdebug 3 default).
            debug_port = 9003,

            -- `:LvimLang serve` — the built-in development web server.
            serve_host = "localhost",
            serve_port = 8000,
            serve_docroot = nil, -- `-t <docroot>`; nil = the project root

            -- intelephense premium (both optional).
            licence_key = nil,
            storage_path = nil, -- on-disk index; nil = intelephense's default under stdpath("cache")

            -- LSP server catalog + selection.
            lsp = {
                servers = {
                    intelephense = {
                        mason = "intelephense",
                        bin = "intelephense",
                        filetypes = { "php" },
                        role = "types",
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
                default = "intelephense", -- string | string[]; "phpactor" to use phpactor instead
            },

            -- Per-filetype formatter / linter / debugger catalog + selection.
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
                    },
                    debuggers = {
                        ["php-debug-adapter"] = { mason = "php-debug-adapter" },
                    },
                    defaults = { formatter = false, linter = false, debugger = "php-debug-adapter" },
                },
            },

            -- Nerd Font icons (statusline / picker rows).
            icons = {
                statusline = "󰌟", -- nf-md-language_php
                test = "󰙨",
                build = "󰜫",
                run = "󰐊",
                debug = "󰃤",
                deps = "󰏗",
            },
        },
    },
})
```
