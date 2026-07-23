# Ruby provider

The Ruby provider owns Ruby tooling through `lvim-lang`: **ruby-lsp** (LSP, solargraph offered as the
alternative), running the current file / `rake` tasks / **rubocop** through **lvim-tasks**, **RSpec**
test running (whole suite / file / example under the cursor), Bundler dependency commands, and
**rdbg** debugging through **lvim-dap**. Everything is resolved per project and lazy — nothing is
wired until the first Ruby buffer is opened.

Filetypes: `ruby`, `eruby`. Project root: `Gemfile` → `Rakefile` → `.ruby-version` → `.git`.

## Toolchain

Ruby installs are managed by a version manager and pinned by the project's `.ruby-version`. Resolved
per project root:

- **`ruby`** — explicit `ruby_path` → lookup cmd → version manager → PATH. The version manager tries
  **mise**, **asdf**, **rbenv** (each `<mgr> which ruby`, run in the project so `.ruby-version` /
  `.tool-versions` wins), then **chruby** / **rvm** (matching `.ruby-version` under `~/.rubies` /
  `~/.rvm/rubies`).
- **`bundle`** / **`rake`** — ship with ruby: the selected ruby's bin dir → PATH.
- **`rubocop`** / **`ruby-lsp`** / **`solargraph`** — gems (also mason packages): explicit path → a
  project binstub (`bin/<tool>`) → the selected ruby's bin → the mason bin → PATH.
- **`rspec`** — a project binstub → the selected ruby's bin → PATH (normally run via `bundle exec`).
- **`rdbg`** — the `debug` gem's binary (`bundle add debug`, **not** mason): explicit path → binstub →
  the selected ruby's bin → PATH.

Nothing is installed here. Ruby is the user's **own** runtime (not lvim-pkg-installed); a missing one
is surfaced at activation and in `:checkhealth` with an install hint.

## Auto-install (the file-open popup)

Opening a Ruby file offers the **active** tools it needs but lacks, through the unified
`lvim-installer` popup: ruby-lsp (LSP), and any chosen efm formatter / linter (rubocop / standardrb).
rdbg is **not** offered — it comes from the project's `debug` gem (`bundle add debug`).

## LSP server catalog

ruby-lsp is the default; solargraph is offered as the alternative (`lsp.server = "solargraph"`, or a
list). ruby-lsp integrates rubocop for formatting + diagnostics natively when rubocop is in the
bundle, so the per-filetype efm formatter / linter default to `false` (the LSP owns them).

| Server | Role | Filetypes |
| --- | --- | --- |
| `ruby-lsp` (default) | types / hover / definition / rename / format / diagnostics | ruby, eruby |
| `solargraph` | alternative full server (completion / hover / definition / format) | ruby |

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `ruby` | rubocop (efm), standardrb (efm) | rubocop (efm), standardrb (efm) | — (rdbg via the `debug` gem) | formatter=false, linter=false, debugger=false |

Selecting an efm formatter (`ft.ruby.formatter = "rubocop"`) makes efm own formatting; ruby-lsp's
formatting capability is switched off on attach so the two never both format the buffer.

## Commands

`:LvimLang <sub> [args]` in a Ruby buffer:

| Command | Description |
| --- | --- |
| `:LvimLang run [args]` | run the current file with `ruby` (`bundle exec` when bundled); applies the active run config |
| `:LvimLang test [args]` | `rspec` — the whole suite |
| `:LvimLang test-file` | run every RSpec example in the current file |
| `:LvimLang test-func` | run the RSpec example under the cursor (`rspec file:line`) |
| `:LvimLang rake [task] [args]` | `rake <task>` (`bundle exec` when bundled) |
| `:LvimLang rubocop [args]` | lint the project |
| `:LvimLang rubocop-fix [args]` | `rubocop -A` — autocorrect |
| `:LvimLang add <gem> [--version …]` | `bundle add` |
| `:LvimLang remove <gem…>` | `bundle remove` |
| `:LvimLang update [gem…]` | `bundle update` |
| `:LvimLang deps <install\|update\|outdated>` | bundler dependency commands |
| `:LvimLang debug` | start / continue an rdbg session |
| `:LvimLang debug-test` | debug the RSpec example under the cursor (rdbg) |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

## Debugging

Debugging uses **rdbg**, the remote debugger from the `debug` gem — add it to the project with
`bundle add debug`. It is **not** a mason package. `:LvimLang debug` starts / continues a session;
`:LvimLang debug-test` runs `bundle exec rspec <file>:<line>` under rdbg for the example under the
cursor and attaches.

## Run configurations

Named configs in `.lvim/lang/run.lua`. `:LvimLang config` picks the active one; `:LvimLang run`
applies its script / args / env.

```lua
return {
    {
        name = "server",
        script = "bin/server.rb", -- the file to run (default: the current buffer)
        args = { "--port", "3000" }, -- program arguments
        env = { RACK_ENV = "development" },
    },
    { name = "default" },
}
```

## Configuration

The complete default `providers.ruby` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        ruby = {
            -- Toolchain (explicit paths win over resolution).
            ruby_path = nil,
            bundle_path = nil,
            rubocop_path = nil,
            ruby_lsp_path = nil,
            rdbg_path = nil,
            ruby_lookup_cmd = nil, -- shell command whose first line is the `ruby` path
            version_manager = nil, -- "mise"|"asdf"|"rbenv"|"chruby"|"rvm"|false|function(root); default: mise→asdf→rbenv→chruby→rvm→PATH
            debug_rspec_command = nil, -- force the rspec command for :LvimLang debug-test (else auto)

            -- LSP server catalog + selection.
            lsp = {
                servers = {
                    ["ruby-lsp"] = {
                        mason = "ruby-lsp",
                        bin = "ruby-lsp",
                        filetypes = { "ruby", "eruby" },
                        role = "types",
                        init_options = {
                            formatter = "auto", -- "auto" | "rubocop" | "syntax_tree" | "none"
                            linters = {}, -- e.g. { "rubocop" }; empty = auto-detect from the bundle
                            enabledFeatures = {
                                codeActions = true,
                                codeLens = true,
                                completion = true,
                                definition = true,
                                diagnostics = true,
                                documentHighlights = true,
                                documentLink = true,
                                documentSymbols = true,
                                foldingRanges = true,
                                formatting = true,
                                hover = true,
                                inlayHint = true,
                                onTypeFormatting = true,
                                selectionRanges = true,
                                semanticHighlighting = true,
                                signatureHelp = true,
                                typeHierarchy = true,
                                workspaceSymbol = true,
                            },
                        },
                    },
                    solargraph = {
                        mason = "solargraph",
                        bin = "solargraph",
                        filetypes = { "ruby" },
                        role = "types",
                        settings = {
                            solargraph = {
                                diagnostics = true,
                                formatting = true,
                                completion = true,
                                hover = true,
                                useBundler = true,
                            },
                        },
                    },
                },
                default = "ruby-lsp", -- string | string[]
            },

            -- Per-filetype formatter / linter / debugger catalog + selection.
            ft = {
                ruby = {
                    formatters = {
                        rubocop = {
                            mason = "rubocop",
                            efm = {
                                formatCommand = "rubocop --stdin ${INPUT} --auto-correct-all --stderr --format quiet",
                                formatStdin = true,
                            },
                        },
                        standardrb = {
                            mason = "standardrb",
                            efm = {
                                formatCommand = "standardrb --stdin ${INPUT} --fix --stderr --format quiet",
                                formatStdin = true,
                            },
                        },
                    },
                    linters = {
                        rubocop = {
                            mason = "rubocop",
                            efm = {
                                lintCommand = "rubocop --stdin ${INPUT} --format emacs --force-exclusion",
                                lintStdin = true,
                                lintFormats = { "%f:%l:%c: %t: %m" },
                                rootMarkers = { ".rubocop.yml", ".rubocop.yaml" },
                            },
                        },
                        standardrb = {
                            mason = "standardrb",
                            efm = {
                                lintCommand = "standardrb --stdin ${INPUT} --format emacs",
                                lintStdin = true,
                                lintFormats = { "%f:%l:%c: %t: %m" },
                            },
                        },
                    },
                    debuggers = {},
                    defaults = { formatter = false, linter = false, debugger = false },
                },
            },

            -- Nerd Font icons (statusline / picker rows).
            icons = {
                statusline = "", -- nf-dev-ruby
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
