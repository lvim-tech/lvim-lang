# Haskell provider

The Haskell provider owns Haskell tooling through `lvim-lang`: **haskell-language-server** (LSP),
`stack` / `cabal` build / run / test / clean and dependency commands through **lvim-tasks**, hspec
test running (whole suite, the file's suites, the `describe`/`it` example under the cursor), and
**haskell-debug-adapter** debugging through **lvim-dap**. Everything is resolved per project and
lazy — nothing is wired until the first Haskell buffer is opened.

Filetypes: `haskell`, `lhaskell`. Project root: `stack.yaml` → `cabal.project` → `package.yaml` →
`.git` (a bare `*.cabal` package is also detected as a Cabal project by the task / test / DAP
modules).

## Build tool

Every runnable action detects the project's build tool at its root, so `stack` and `cabal`
projects both work without configuration:

- **`stack.yaml`** present → **Stack** (`stack build|run|test|clean`).
- **`cabal.project`** or any **`*.cabal`** present → **Cabal** (`cabal build|run|test|clean`).
- Stack is preferred when a project ships both (the tool the author committed to).

## Toolchain

Haskell is the user's **own** toolchain — installed and switched almost universally through
**GHCup** (which also provides cabal / stack / HLS), and often through mise / asdf. Resolved per
project root (first executable wins):

- **`ghc`** — explicit path → `ghc_lookup_cmd` → version manager → the GHCup bin dir → PATH.
- **`cabal`** / **`stack`** — explicit path → version manager → the GHCup bin dir → PATH.
- **`haskell-language-server`** — explicit path → version manager → the GHCup bin dir
  (`haskell-language-server-wrapper`) → the mason bin → PATH.
- **`fourmolu`** / **`ormolu`** / **`hlint`** / **`haskell-debug-adapter`** — explicit path → PATH
  (the formatters / linter / adapter are mason packages, not part of the toolchain).

The version manager (`version_manager`) is `"ghcup"` | `"mise"` | `"asdf"` | `false` |
`function(root, tool)`; the default tries GHCup (`ghcup whereis <component>`), then mise / asdf.
Nothing is installed here.

## Auto-install (the file-open popup)

Opening a Haskell file offers the **active** tools it needs but lacks, through the unified
`lvim-installer` popup: haskell-language-server (LSP) and the chosen debugger
(**haskell-debug-adapter**). GHC / cabal / stack are the user's own toolchain (installed via GHCup)
and are surfaced as requirements, not auto-installed. fourmolu / ormolu / hlint are opt-in efm
tools (HLS formats + lints natively by default).

## LSP server catalog

haskell-language-server is the single Haskell server (the mason `haskell-language-server` package
installs a `haskell-language-server-wrapper` that selects the right HLS build for the project's
GHC; the server is launched as `<wrapper> --lsp`). HLS formats Haskell natively (its ormolu /
fourmolu plugin) and surfaces hlint suggestions inline, so the default formatter and linter are
`false`.

| Server | Role | Filetypes |
| --- | --- | --- |
| `haskell-language-server` (default) | types / hover / definition / rename / inlay hints / format / hlint | haskell, lhaskell |

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `haskell` | fourmolu, ormolu (efm) | hlint (efm) | haskell-debug-adapter | formatter=false, linter=false, debugger=haskell-debug-adapter |
| `lhaskell` | fourmolu, ormolu (efm) | hlint (efm) | haskell-debug-adapter | formatter=false, linter=false, debugger=haskell-debug-adapter |

## Commands

`:LvimLang <sub> [args]` in a Haskell buffer:

| Command | Description |
| --- | --- |
| `:LvimLang build [args]` | `stack build` / `cabal build` |
| `:LvimLang run [args]` | `stack run` / `cabal run` (applies the active run config) |
| `:LvimLang test [args]` | `stack test` / `cabal test` — the whole suite |
| `:LvimLang test-func` | run the hspec `describe`/`it` example under the cursor (`--match "/…/"`) |
| `:LvimLang test-file` | run the current file's top-level hspec suites |
| `:LvimLang clean [args]` | `stack clean` / `cabal clean` |
| `:LvimLang deps <resolve\|freeze\|list\|outdated>` | dependency resolution / inspection |
| `:LvimLang debug` | start / continue a haskell-debug-adapter session |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

### Dependencies

Haskell has no clean, non-destructive **add / remove** CLI (unlike cargo / npm) — dependencies live
in the package's `*.cabal` `build-depends` (or a hpack `package.yaml`), so you add / remove one by
editing that file. `:LvimLang deps` exposes only the safe read / resolve operations:

- `resolve` — fetch + build only the dependencies (`stack build --only-dependencies` /
  `cabal build --only-dependencies`).
- `freeze` — pin an exact plan (`cabal freeze`; Stack pins via its resolver in `stack.yaml`).
- `list` — the resolved dependency set (`stack ls dependencies`; Cabal has no first-party flat
  list — use the external `cabal-plan`).
- `outdated` — `cabal outdated` (Stack follows its resolver).

### Tests (hspec)

`:LvimLang test-func` recovers the `describe` / `context` / `it` / `specify` / `prop` path under the
cursor from treesitter and runs `hspec --match "/describe/…/it/"`. The match reaches the test
executable through **Cabal's** repeatable `--test-option=` (each value is its own argv, so labels
with spaces survive intact) or **Stack's** `--test-arguments` string (Stack word-splits it, so a
label containing spaces can mis-split there — a Stack limitation; Cabal is the exact path).

## Debugging

`:LvimLang debug` drives **haskell-debug-adapter** (phoityne), a GHCi-driven DAP server. The launch
config loads the current file (`startup`) into a GHCi session started with the tool-appropriate
command (`stack ghci …` / `cabal exec -- ghci …`, both with `-fprint-evld-with-show`). phoityne is
sensitive to the project's exact GHCi invocation — a project with a bespoke test / exe target may
need `providers.haskell.dap.stack_ghci_cmd` / `cabal_ghci_cmd` tuned.

## Run configurations

Named configs in `.lvim/lang/run.lua`. `:LvimLang config` picks the active one; `:LvimLang run`
applies its target / build flags / args / env.

```lua
return {
    {
        name = "server",
        target = "myapp-exe", -- the executable target (stack target / .cabal executable stanza)
        build_flags = { "--fast" }, -- extra build-tool flags (before --)
        args = { "--port", "8080" }, -- program arguments (after --)
        env = { LOG_LEVEL = "debug" },
    },
    { name = "default" },
}
```

## Configuration

The complete default `providers.haskell` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        haskell = {
            -- Toolchain (explicit paths win over resolution).
            ghc_path = nil,
            cabal_path = nil,
            stack_path = nil,
            hls_path = nil, -- the haskell-language-server(-wrapper) binary
            fourmolu_path = nil,
            ormolu_path = nil,
            hlint_path = nil,
            ghc_lookup_cmd = nil, -- shell command whose first line is the `ghc` path
            version_manager = nil, -- "ghcup" | "mise" | "asdf" | false | function(root, tool); default: ghcup→mise→asdf→GHCup bin→PATH

            -- Debugging (haskell-debug-adapter / phoityne).
            dap = {
                haskell_debug_adapter_path = nil, -- explicit adapter binary (nil = toolchain / PATH / mason)
                adapter_args = {}, -- extra argv for the adapter process
                stack_ghci_cmd = "stack ghci --test --no-load --no-build --main-is TARGET --ghci-options -fprint-evld-with-show",
                cabal_ghci_cmd = "cabal exec -- ghci -fprint-evld-with-show",
                ghci_prompt = "λλλλ> ",
                ghci_initial_prompt = nil, -- nil = reuse ghci_prompt
                ghci_env = nil, -- table<string,string> passed to the GHCi session (nil = none)
                startup_func = "", -- phoityne startupFunc
                startup_args = "", -- args for startup_func
                stop_on_entry = true,
                log_file = nil, -- nil = stdpath("cache")/lvim-lang-haskell-dap.log
                log_level = "WARNING",
            },

            -- LSP server catalog + selection.
            lsp = {
                servers = {
                    ["haskell-language-server"] = {
                        mason = "haskell-language-server",
                        bin = "haskell-language-server-wrapper",
                        filetypes = { "haskell", "lhaskell" },
                        role = "types",
                        settings = {
                            haskell = {
                                formattingProvider = "ormolu", -- "ormolu" | "fourmolu" | "stylish-haskell" | "brittany" | "floskell" | "none"
                                checkParents = "CheckOnSave",
                                checkProject = true,
                                plugin = {
                                    hlint = { globalOn = true }, -- inline hlint suggestions
                                },
                            },
                        },
                    },
                },
                default = "haskell-language-server", -- string | string[]
            },

            -- Per-filetype formatter / linter / debugger catalog + selection.
            ft = {
                haskell = {
                    formatters = {
                        fourmolu = {
                            mason = "fourmolu",
                            efm = { formatCommand = "fourmolu --stdin-input-file ${INPUT}", formatStdin = true },
                        },
                        ormolu = {
                            mason = "ormolu",
                            efm = { formatCommand = "ormolu --stdin-input-file ${INPUT}", formatStdin = true },
                        },
                    },
                    linters = {
                        hlint = {
                            mason = "hlint",
                            efm = {
                                lintCommand = "hlint ${INPUT}",
                                lintStdin = false,
                                lintFormats = {
                                    "%f:%l:%c-%*[0-9]: %trror: %m",
                                    "%f:%l:%c-%*[0-9]: %tarning: %m",
                                    "%f:%l:%c: %trror: %m",
                                    "%f:%l:%c: %tarning: %m",
                                },
                            },
                        },
                    },
                    debuggers = {
                        ["haskell-debug-adapter"] = { mason = "haskell-debug-adapter" },
                    },
                    -- HLS formats + lints natively, so the defaults are false.
                    defaults = { formatter = false, linter = false, debugger = "haskell-debug-adapter" },
                },
                -- lhaskell mirrors the haskell block (same tools).
                lhaskell = {
                    formatters = {
                        fourmolu = {
                            mason = "fourmolu",
                            efm = { formatCommand = "fourmolu --stdin-input-file ${INPUT}", formatStdin = true },
                        },
                        ormolu = {
                            mason = "ormolu",
                            efm = { formatCommand = "ormolu --stdin-input-file ${INPUT}", formatStdin = true },
                        },
                    },
                    linters = {
                        hlint = {
                            mason = "hlint",
                            efm = {
                                lintCommand = "hlint ${INPUT}",
                                lintStdin = false,
                                lintFormats = {
                                    "%f:%l:%c-%*[0-9]: %trror: %m",
                                    "%f:%l:%c-%*[0-9]: %tarning: %m",
                                    "%f:%l:%c: %trror: %m",
                                    "%f:%l:%c: %tarning: %m",
                                },
                            },
                        },
                    },
                    debuggers = {
                        ["haskell-debug-adapter"] = { mason = "haskell-debug-adapter" },
                    },
                    defaults = { formatter = false, linter = false, debugger = "haskell-debug-adapter" },
                },
            },

            -- Icons (Nerd Font).
            icons = {
                statusline = "",
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

## Available Haskell packages (mason registry)

| Category | In the catalog | Also in the registry / toolchain |
| --- | --- | --- |
| LSP | haskell-language-server | — |
| Formatter | fourmolu, ormolu | — |
| Linter | hlint | — |
| DAP | haskell-debug-adapter | — |
| Toolchain | — | ghc, cabal, stack (via GHCup — the user's own) |
