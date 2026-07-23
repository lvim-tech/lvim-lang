# TypeScript / JavaScript provider

The TypeScript / JavaScript provider owns JS/TS tooling through `lvim-lang`: a **multi-LSP** setup —
**vtsls** (types / hover / completion / code actions) **and** the **eslint** language server (lint
diagnostics + fix-all) attaching to the same buffer — with **prettier** formatting through
**efm-langserver**, package-manager-aware `run` / `script` / `install` / `build` / `dev` through
**lvim-tasks**, **vitest** / **jest** test running (whole suite, current file, the test under the
cursor), a coverage gutter overlay, `npm` / `pnpm` / `yarn` / `bun` dependency management
(auto-detected), `.d.ts` generation (**tsc**), and **js-debug** debugging through **lvim-dap**.
Everything is **project-local first** (a repo's `node_modules/.bin` tools win) and resolved per
project — lazy: nothing is wired until the first JS/TS buffer is opened.

Filetypes: `typescript`, `typescriptreact`, `javascript`, `javascriptreact`. Project root:
`package.json` → `tsconfig.json` → `jsconfig.json` → `.git`.

## Toolchain (project-local first)

Resolved per project root:

- **`node`** — an explicit `node_path` → a `node_lookup_cmd` → a **version manager** (`mise` / `asdf`
  / `fnm`, honouring the project's pin) → `PATH`.
- **`vtsls`** / **`eslint`** (the servers) — an explicit path → the mason bin → `PATH`.
- **`prettier`** / **`tsc`** / **`vitest`** / **`jest`** — the project's **`node_modules/.bin`** →
  the mason bin → `PATH`. A repo's pinned tool always wins.

The package manager (**npm** / **pnpm** / **yarn** / **bun**) is detected from the lockfile (or the
corepack `packageManager` field), unless pinned via `package_manager`.

## Auto-install (the file-open popup)

Opening a JS/TS file offers the **active** tools it needs but lacks, through the unified
`lvim-installer` popup: the chosen **LSP servers** (vtsls + eslint), the chosen **formatter**
(prettier), and the chosen **debugger** (js-debug-adapter). All are mason-registry packages installed
by `lvim-pkg`'s own handlers — no `mason.nvim`.

## LSP server catalog

The default is a **list** — vtsls (types) + the eslint LSP (lint). prettier owns formatting, so both
servers' own formatting is switched off automatically (an efm formatter is active). Set
`lsp.server = "vtsls"` to run a single server. (The eslint server needs `eslint` installed in the
project to actually lint; with none it no-ops.)

| Server | Role | Filetypes |
| --- | --- | --- |
| `vtsls` (default) | types / hover / completion / definition / rename / inlay hints / code actions | ts, tsx, js, jsx |
| `eslint` (default) | eslint lint diagnostics + fix-all | ts, tsx, js, jsx |

## Per-filetype catalog

The four filetypes share one catalog. prettier is the default formatter (efm); linting is by the
eslint LSP (so no default efm linter). The catalog still offers efm alternatives (prettierd / biome /
dprint formatters; eslint_d / biome / oxlint linters).

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| ts / tsx / js / jsx | prettier, prettierd, biome, dprint | eslint_d, biome, oxlint | js-debug-adapter | formatter=prettier, linter=false, debugger=js-debug-adapter |

## Commands

`:LvimLang <sub> [args]` in a JS/TS buffer:

| Command | Description |
| --- | --- |
| `:LvimLang run [args]` | run the current file (node / a project-local tsx) or the active run config |
| `:LvimLang script [name] [args]` | run a package.json script (`<pm> run <name>`; picker if no name) |
| `:LvimLang install [args]` | install dependencies (`<pm> install`) |
| `:LvimLang build [args]` | run the `build` script |
| `:LvimLang dev [args]` | run the `dev` script |
| `:LvimLang test [args]` | run the whole suite (vitest / jest) |
| `:LvimLang test-file` | run the current file's tests |
| `:LvimLang test-func` | run the `it()` / `test()` under the cursor (`-t <title>`) |
| `:LvimLang coverage [clear]` | run with a JSON coverage reporter + a green/red gutter overlay |
| `:LvimLang add <package…>` | add a dependency (auto-detected manager) |
| `:LvimLang remove <package…>` | remove a dependency |
| `:LvimLang update [package…]` | update dependencies |
| `:LvimLang deps <install\|update\|outdated>` | dependency commands |
| `:LvimLang types [args]` | emit `.d.ts` declarations (`tsc --declaration --emitDeclarationOnly`) |
| `:LvimLang debug` | start / continue a js-debug session |
| `:LvimLang debug-test` | debug the test under the cursor |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

## Run configurations

Named configs in `.lvim/lang/run.lua` (a pure-data file). `:LvimLang config` picks the active one
(remembered per project); `:LvimLang run` applies it.

```lua
return {
    {
        name = "dev",
        script = "dev", -- run a package.json script (`<pm> run dev`)
        env = { NODE_ENV = "development" },
    },
    {
        name = "seed",
        file = "scripts/seed.ts", -- run a file (node / tsx)
        args = { "--force" },
    },
}
```

## Configuration

The complete default `providers.typescript` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        typescript = {
            -- Toolchain (explicit paths win over resolution).
            node_path = nil,
            vtsls_path = nil,
            eslint_lsp_path = nil,
            prettier_path = nil,
            node_lookup_cmd = nil, -- shell command whose first line is the `node` path
            version_manager = nil, -- "mise"|"asdf"|"fnm"|false|function(root); default: mise→asdf→fnm→PATH

            -- LSP server catalog + selection (the default is a LIST — multi-LSP).
            lsp = {
                servers = {
                    vtsls = {
                        mason = "vtsls",
                        bin = "vtsls",
                        filetypes = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
                        role = "types",
                        settings = {
                            typescript = {
                                inlayHints = {
                                    parameterNames = { enabled = "literals" },
                                    parameterTypes = { enabled = true },
                                    variableTypes = { enabled = false },
                                    propertyDeclarationTypes = { enabled = true },
                                    functionLikeReturnTypes = { enabled = true },
                                    enumMemberValues = { enabled = true },
                                },
                                updateImportsOnFileMove = { enabled = "always" },
                                preferences = { importModuleSpecifier = "non-relative" },
                            },
                            javascript = {
                                inlayHints = {
                                    parameterNames = { enabled = "literals" },
                                    parameterTypes = { enabled = true },
                                    functionLikeReturnTypes = { enabled = true },
                                },
                            },
                            vtsls = { experimental = { completion = { enableServerSideFuzzyMatch = true } } },
                        },
                    },
                    eslint = {
                        mason = "eslint-lsp",
                        bin = "vscode-eslint-language-server",
                        filetypes = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
                        role = "diagnostics",
                        -- vscode-eslint requests config SECTION-LESS → these sit at the TOP LEVEL of
                        -- `settings` (not nested under `eslint`); the server module injects
                        -- workspaceFolder / nodePath / experimental.useFlatConfig per project root.
                        settings = {
                            validate = "on",
                            run = "onType",
                            format = false, -- prettier owns formatting
                            quiet = false,
                            onIgnoredFiles = "off",
                            useESLintClass = false,
                            nodePath = "",
                            rulesCustomizations = {},
                            problems = { shortenToSingleLine = false },
                            workingDirectory = { mode = "location" },
                            codeActionOnSave = { enable = false, mode = "all" },
                            codeAction = {
                                disableRuleComment = { enable = true, location = "separateLine" },
                                showDocumentation = { enable = true },
                            },
                        },
                    },
                },
                default = { "vtsls", "eslint" }, -- string | string[] (a list attaches several clients)
            },

            -- Per-filetype catalog (all four filetypes share this block).
            ft = {
                -- typescript / typescriptreact / javascript / javascriptreact each carry:
                typescript = {
                    formatters = {
                        prettier = {
                            mason = "prettier",
                            efm = { formatCommand = "prettier --stdin-filepath ${INPUT}", formatStdin = true },
                        },
                        prettierd = {
                            mason = "prettierd",
                            efm = { formatCommand = "prettierd ${INPUT}", formatStdin = true },
                        },
                        biome = {
                            mason = "biome",
                            efm = { formatCommand = "biome format --stdin-file-path ${INPUT}", formatStdin = true },
                        },
                        dprint = {
                            mason = "dprint",
                            efm = { formatCommand = "dprint fmt --stdin ${INPUT}", formatStdin = true },
                        },
                    },
                    linters = {
                        eslint_d = {
                            mason = "eslint_d",
                            efm = {
                                lintCommand = "eslint_d --no-color --format compact --stdin --stdin-filename ${INPUT}",
                                lintStdin = true,
                                lintIgnoreExitCode = true,
                                lintFormats = {
                                    "%f: line %l, col %c, %trror - %m",
                                    "%f: line %l, col %c, %tarning - %m",
                                },
                                rootMarkers = {
                                    ".eslintrc",
                                    ".eslintrc.js",
                                    ".eslintrc.cjs",
                                    ".eslintrc.json",
                                    "eslint.config.js",
                                },
                            },
                        },
                        biome = {
                            mason = "biome",
                            efm = {
                                lintCommand = "biome lint --stdin-file-path ${INPUT}",
                                lintStdin = true,
                                lintFormats = { "%f:%l:%c %m" },
                            },
                        },
                        oxlint = {
                            mason = "oxlint",
                            efm = {
                                lintCommand = "oxlint ${INPUT}",
                                lintStdin = false,
                                lintFormats = { "%f:%l:%c %m" },
                            },
                        },
                    },
                    debuggers = { ["js-debug-adapter"] = { mason = "js-debug-adapter" } },
                    -- Only the chosen tools install / wire (false = none). prettier formats; eslint-LSP lints.
                    defaults = { formatter = "prettier", linter = false, debugger = "js-debug-adapter" },
                },
                -- (typescriptreact / javascript / javascriptreact are identical copies)
            },

            -- `:LvimLang types` emits `.d.ts` via tsc (resolved through the toolchain) — no upfront install.
            codegen = {},

            -- Package manager: "auto" detects it; pin to "npm"|"pnpm"|"yarn"|"bun".
            package_manager = "auto",
            -- Test runner: "auto" detects vitest / jest; pin to "vitest"|"jest".
            test_runner = "auto",

            -- Statusline / picker icons (Nerd Font).
            icons = {
                statusline = "󰛦",
                test = "󰙨",
                run = "󰐊",
                debug = "󰃤",
                deps = "󰏗",
                script = "󰜎",
                pm = "󰎙",
            },
        },
    },
})
```

## Available JS/TS packages (mason registry)

Filter `languages = TypeScript / JavaScript`. In the catalog you pick from these; more exist in the
registry and can be added to the catalog.

| Category | In the catalog | Also in the registry |
| --- | --- | --- |
| LSP | vtsls, eslint-lsp | typescript-language-server (ts_ls), biome, denols, quick-lint-js |
| Formatter | prettier, prettierd, biome, dprint | — |
| Linter | eslint_d, biome, oxlint | standardjs, quick-lint-js, semgrep |
| DAP | js-debug-adapter | firefox-debug-adapter, chrome-debug-adapter |
