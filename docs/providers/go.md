# Go provider

The Go provider owns Go tooling through `lvim-lang`: **gopls** (LSP), formatters / linters routed
per filetype through **efm-langserver**, `go` build / run / test / vet / generate and `go mod`
commands through **lvim-tasks**, coverage overlays, code generation (**gomodifytags** / **gotests**
/ **impl**), and **Delve** debugging through **lvim-dap**. Everything is resolved per project and
lazy — nothing is wired until the first Go buffer is opened.

Filetypes: `go`, `gomod`, `gowork`, `gotmpl`. Project root: `go.work` → `go.mod` → `.git`.

## Toolchain

Resolved per project root (nothing is installed here — see the install popup below):

- **`go`** — an explicit `go_path` → a `go_lookup_cmd` → a **version manager** (`mise` / `asdf`,
  honouring the project's pinned version) → `PATH`.
- **`gopls`** / **`dlv`** — an explicit path → `go env GOBIN` / `GOPATH/bin` (where `go install`
  drops them) → `PATH`.

## Auto-install (the file-open popup)

Opening a Go file offers the **active** tools it needs but lacks, through the unified
`lvim-installer` popup (the same one for every filetype): the chosen **LSP server** (gopls), the
chosen **linter** (golangci-lint), the chosen **debugger** (delve), and a **formatter** if you
select one. All are mason-registry packages installed by `lvim-pkg`'s own handlers — no
`mason.nvim`. Codegen tools are **on-demand** (installed the first time you run their command),
unless you mark one `active = true` to move it into this popup.

## LSP server catalog

gopls is the default. `lsp.default` may be a **string or a list** (several LSP clients attach to
the same buffer). When a formatter is active for a filetype, the LSP's own formatting is switched
off automatically so the two don't both format.

| Server | Role | Filetypes |
| --- | --- | --- |
| `gopls` (default) | types / hover / definition / rename / inlay hints / format | go, gomod, gowork, gotmpl |
| `golangci-lint-langserver` | LSP-based linting (alternative to the efm linter) | go |

## Per-filetype catalog

Each filetype has its own catalog; you pick a default (or `false` for none). Only the chosen tools
are installed / wired. Formatting on Go is done by **gopls** natively (`gofumpt = true`), so the
default formatter is `false`; the catalog still offers efm formatters.

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `go` | gofumpt, goimports, golines, gci, goimports-reviser | golangci-lint, revive, staticcheck | delve, go-debug-adapter | formatter=false, linter=golangci-lint, debugger=delve |
| `gomod` | — | golangci-lint | — | linter=false (opt-in) |
| `gowork` | — | — | — | — |
| `gotmpl` | — | — | — | — |

## Commands

`:LvimLang <sub> [args]` in a Go buffer:

| Command | Description |
| --- | --- |
| `:LvimLang build [args]` | `go build ./...` |
| `:LvimLang run [target] [args]` | `go run .` (or a target); applies the active run config |
| `:LvimLang test [args]` | `go test ./...` |
| `:LvimLang test-func` | run the Test/Benchmark/Fuzz/Example under the cursor |
| `:LvimLang test-file` | `go test` the current buffer's package |
| `:LvimLang coverage [clear]` | `go test -coverprofile` + a green/red gutter overlay |
| `:LvimLang vet` | `go vet ./...` |
| `:LvimLang generate` | `go generate ./...` |
| `:LvimLang mod <tidy\|download\|verify\|graph\|why>` | `go mod …` |
| `:LvimLang get <module[@version]> \| -u ./...` | `go get` (add / upgrade) |
| `:LvimLang tags <add\|remove> [json\|xml\|…]` | struct tags at the cursor (gomodifytags) |
| `:LvimLang gotests` | generate a table-driven test for the function at the cursor |
| `:LvimLang impl <receiver…> <interface>` | interface method stubs (e.g. `impl r *Server io.Reader`) |
| `:LvimLang debug` | start / continue a Delve session |
| `:LvimLang debug-test` | debug the test under the cursor (`-test.run ^Name$`) |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

## Run configurations

Named configs in `.lvim/lang/run.lua` (a pure-data file). `:LvimLang config` picks the active one
(remembered per project); `:LvimLang run` applies its package / build flags / tags / args / env.

```lua
return {
    {
        name = "server",
        package = "./cmd/server", -- what to run (a package path)
        build_flags = { "-race" }, -- extra `go run` flags
        tags = { "dev", "netgo" }, -- build tags → -tags dev,netgo
        args = { "--verbose" }, -- program arguments
        env = { PORT = "8080" }, -- process environment
    },
    { name = "main", package = "." },
}
```

## Configuration

The complete default `providers.go` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        go = {
            -- Toolchain (explicit paths win over resolution).
            go_path = nil,
            gopls_path = nil,
            dlv_path = nil,
            go_lookup_cmd = nil, -- shell command whose first line is the `go` path
            version_manager = nil, -- "mise" | "asdf" | false | function(root); default: mise→asdf→PATH

            -- LSP server catalog + selection.
            lsp = {
                servers = {
                    gopls = {
                        mason = "gopls",
                        filetypes = { "go", "gomod", "gowork", "gotmpl" },
                        role = "types",
                        settings = {
                            gopls = {
                                hints = {
                                    assignVariableTypes = true,
                                    compositeLiteralFields = true,
                                    constantValues = true,
                                    functionTypeParameters = true,
                                    parameterNames = true,
                                    rangeVariableTypes = true,
                                },
                                analyses = {
                                    unusedparams = true,
                                    shadow = true,
                                    nilness = true,
                                    unusedwrite = true,
                                    useany = true,
                                },
                                staticcheck = true,
                                gofumpt = true,
                                semanticTokens = true,
                                usePlaceholders = true,
                                completeUnimported = true,
                                codelenses = {
                                    generate = true,
                                    gc_details = true,
                                    test = true,
                                    tidy = true,
                                    upgrade_dependency = true,
                                    regenerate_cgo = true,
                                    run_govulncheck = true,
                                    vendor = true,
                                },
                            },
                        },
                    },
                    ["golangci-lint-langserver"] = {
                        mason = "golangci-lint-langserver",
                        filetypes = { "go" },
                        role = "diagnostics",
                        settings = {},
                    },
                },
                default = "gopls", -- string | string[] (a list attaches several LSP clients)
            },

            -- Per-filetype formatter / linter / debugger catalog + selection.
            ft = {
                go = {
                    formatters = {
                        gofumpt = { mason = "gofumpt", efm = { formatCommand = "gofumpt", formatStdin = true } },
                        goimports = { mason = "goimports", efm = { formatCommand = "goimports", formatStdin = true } },
                        golines = {
                            mason = "golines",
                            efm = { formatCommand = "golines --max-len=120", formatStdin = true },
                        },
                        gci = { mason = "gci", efm = { formatCommand = "gci print", formatStdin = true } },
                        ["goimports-reviser"] = {
                            mason = "goimports-reviser",
                            efm = { formatCommand = "goimports-reviser -output stdout ${INPUT}", formatStdin = false },
                        },
                    },
                    linters = {
                        ["golangci-lint"] = {
                            mason = "golangci-lint",
                            efm = {
                                lintCommand = "golangci-lint run --output.text.path stdout --show-stats=false --output.text.print-issued-lines=false",
                                lintStdin = false,
                                lintFormats = { "%f:%l:%c: %m" },
                                rootMarkers = { ".golangci.yml", ".golangci.yaml", ".golangci.toml", ".golangci.json" },
                            },
                        },
                        revive = {
                            mason = "revive",
                            efm = {
                                lintCommand = "revive ${INPUT}",
                                lintStdin = false,
                                lintFormats = { "%f:%l:%c: %m" },
                            },
                        },
                        staticcheck = {
                            mason = "staticcheck",
                            efm = {
                                lintCommand = "staticcheck ${INPUT}",
                                lintStdin = false,
                                lintFormats = { "%f:%l:%c: %m" },
                            },
                        },
                    },
                    debuggers = {
                        delve = { mason = "delve", bin = "dlv" },
                        ["go-debug-adapter"] = { mason = "go-debug-adapter" },
                    },
                    -- Only the chosen tools install / wire (false = none). gopls formats Go natively.
                    defaults = { formatter = false, linter = "golangci-lint", debugger = "delve" },
                },
                gomod = {
                    linters = {
                        ["golangci-lint"] = {
                            mason = "golangci-lint",
                            efm = {
                                lintCommand = "golangci-lint run --output.text.path stdout --show-stats=false --output.text.print-issued-lines=false",
                                lintStdin = false,
                                lintFormats = { "%f:%l:%c: %m" },
                            },
                        },
                    },
                    defaults = { linter = false },
                },
                gowork = { defaults = {} },
                gotmpl = { defaults = {} },
            },

            -- Codegen tools. On-demand by default; `active = true` installs one upfront (in the popup).
            codegen = {
                gomodifytags = { mason = "gomodifytags" }, -- add `active = true` to install upfront
                gotests = { mason = "gotests" },
                impl = { mason = "impl" },
            },

            -- Statusline / picker icons (Nerd Font).
            icons = {
                statusline = "",
                test = "",
                build = "",
                run = "󰐊",
                debug = "",
                mod = "",
                tags = "󰓹",
            },
        },
    },
})
```

## Available Go packages (mason registry)

Filter `languages = Go`. In the catalog you pick from these; more exist in the registry and can be
added to the catalog.

| Category | In the catalog | Also in the registry |
| --- | --- | --- |
| LSP | gopls, golangci-lint-langserver | templ |
| Formatter | gofumpt, goimports, golines, gci, goimports-reviser | crlfmt |
| Linter | golangci-lint, revive, staticcheck | nilaway, gospel, semgrep |
| DAP | delve (dlv), go-debug-adapter | — |
| Codegen | gomodifytags, gotests, impl | — |
