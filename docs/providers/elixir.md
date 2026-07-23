# Elixir provider

The Elixir provider owns Elixir tooling through `lvim-lang`: **elixir-ls** (LSP, with **lexical** and
**next-ls** offered as alternatives), running `mix compile` / `mix run` / `iex -S mix` / `mix format` /
`mix credo` through **lvim-tasks**, **ExUnit** test running (whole suite / file / test under the
cursor), Hex/mix dependency commands, and **elixir-ls** debugging through **lvim-dap**. Everything is
resolved per project and lazy — nothing is wired until the first Elixir buffer is opened.

Filetypes: `elixir`, `eelixir`, `heex`. Project root: `mix.exs` → `.git`.

## Toolchain

Elixir installs are managed by a version manager and pinned by the project's `.tool-versions`.
Resolved per project root:

- **`elixir`** — explicit `elixir_path` → lookup cmd → version manager → PATH. The version manager
  tries **mise**, then **asdf** (each `<mgr> which elixir`, run in the project so `.tool-versions`
  wins).
- **`mix`** / **`iex`** — ship with elixir: the selected elixir's bin dir → version manager → PATH.
- **`elixir-ls`** / **`lexical`** / **`nextls`** — mason packages: explicit path → the mason bin →
  PATH.
- **`elixir-ls-debugger`** — the debug adapter that ships as a second binary inside the elixir-ls
  mason package: explicit path → the mason bin → PATH.

Nothing is installed here. Elixir is the user's **own** runtime (not lvim-pkg-installed); a missing one
is surfaced at activation and in `:checkhealth` with an install hint.

## Auto-install (the file-open popup)

Opening an Elixir file offers the **active** tools it needs but lacks, through the unified
`lvim-installer` popup: the chosen LSP server (elixir-ls by default), the elixir-ls debugger, and any
chosen efm formatter / linter (`mix format` / credo). The Elixir runtime itself is never installed —
it is the user's own.

## LSP server catalog

elixir-ls is the default; lexical and next-ls are offered as alternatives (`lsp.server = "lexical"`,
or a list). elixir-ls drives `mix format` and reports credo/dialyzer diagnostics natively, so the
per-filetype efm formatter / linter default to `false` (the LSP owns them).

| Server | Role | Filetypes |
| --- | --- | --- |
| `elixir-ls` (default) | types / hover / definition / rename / format / diagnostics | elixir, eelixir, heex |
| `lexical` | alternative full server (completion / hover / definition / format) | elixir, eelixir, heex |
| `next-ls` | alternative full server (elixir-tools' Next LS; binary `nextls --stdio`) | elixir, eelixir, heex |

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `elixir` | mix_format (efm) | credo (efm) | elixir-ls (elixir-ls-debugger) | formatter=false, linter=false, debugger=elixir-ls |

Selecting an efm formatter (`ft.elixir.formatter = "mix_format"`) makes efm own formatting; the LSP's
formatting capability is switched off on attach so the two never both format the buffer.

## Commands

`:LvimLang <sub> [args]` in an Elixir buffer:

| Command | Description |
| --- | --- |
| `:LvimLang compile [args]` | `mix compile` |
| `:LvimLang run [args]` | `mix run` (applies the active run config — its `task` / args / env) |
| `:LvimLang iex [args]` | `iex -S mix` — an interactive shell in the project |
| `:LvimLang format [args]` | `mix format` |
| `:LvimLang credo [args]` | `mix credo` — static analysis / linting (defaults to `--strict`) |
| `:LvimLang test [args]` | `mix test` — the whole suite |
| `:LvimLang test-file` | run every ExUnit test in the current file |
| `:LvimLang test-func` | run the ExUnit test under the cursor (`mix test file:line`) |
| `:LvimLang deps <get\|update\|tree\|clean\|unlock>` | Hex/mix dependency commands |
| `:LvimLang debug` | start / continue an elixir-ls debug session |
| `:LvimLang debug-test` | debug the ExUnit test under the cursor (elixir-ls) |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

mix has no `add` / `remove` verb — dependencies are declared by hand in `mix.exs`'s `deps/0`, so only
the lifecycle verbs are exposed.

## Debugging

Debugging uses the **elixir-ls debugger** — a standalone DAP adapter (`elixir-ls-debugger`) that ships
as a second binary inside the elixir-ls mason package, independent of the language server, so it works
whichever LSP (elixir-ls / lexical / next-ls) is chosen. Its launch request is a `mix_task`: it starts
the app and runs a mix task (`test`, `run`, `phx.server`, …) under the debugger. `:LvimLang debug`
starts / continues a session; `:LvimLang debug-test` runs `mix test <file>:<line>` under the adapter
for the test under the cursor and attaches.

## Run configurations

Named configs in `.lvim/lang/run.lua`. `:LvimLang config` picks the active one; `:LvimLang run`
applies its mix `task` / args / env.

```lua
return {
    {
        name = "server",
        task = "phx.server", -- the mix task to run (default: "run")
        args = {}, -- extra task arguments
        env = { MIX_ENV = "dev" },
    },
    { name = "default" },
}
```

## Configuration

The complete default `providers.elixir` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        elixir = {
            -- Toolchain (explicit paths win over resolution).
            elixir_path = nil,
            mix_path = nil,
            elixir_ls_path = nil,
            elixir_ls_debugger_path = nil,
            elixir_lookup_cmd = nil, -- shell command whose first line is the `elixir` path
            version_manager = nil, -- "mise"|"asdf"|false|function(root, tool); default: mise→asdf→PATH

            -- Debug adapter tuning.
            dap = {
                test_require_files = { "test/**/test_helper.exs", "test/**/*_test.exs" },
            },

            -- LSP server catalog + selection.
            lsp = {
                servers = {
                    ["elixir-ls"] = {
                        mason = "elixir-ls",
                        bin = "elixir-ls",
                        filetypes = { "elixir", "eelixir", "heex" },
                        role = "types",
                        settings = {
                            elixirLS = {
                                dialyzerEnabled = true,
                                dialyzerFormat = "dialyxir_long",
                                fetchDeps = false,
                                enableTestLenses = false,
                                suggestSpecs = true,
                                mixEnv = "test",
                                autoInsertRequiredAlias = true,
                            },
                        },
                    },
                    lexical = {
                        mason = "lexical",
                        bin = "lexical",
                        filetypes = { "elixir", "eelixir", "heex" },
                        role = "types",
                        settings = {},
                    },
                    ["next-ls"] = {
                        mason = "next-ls",
                        bin = "nextls",
                        filetypes = { "elixir", "eelixir", "heex" },
                        role = "types",
                        settings = {},
                    },
                },
                default = "elixir-ls", -- string | string[]
            },

            -- Per-filetype formatter / linter / debugger catalog + selection.
            ft = {
                elixir = {
                    formatters = {
                        mix_format = {
                            efm = {
                                formatCommand = "mix format -",
                                formatStdin = true,
                                rootMarkers = { "mix.exs", ".formatter.exs" },
                            },
                        },
                    },
                    linters = {
                        credo = {
                            efm = {
                                lintCommand = "mix credo suggest --format=flycheck --read-from-stdin ${INPUT}",
                                lintStdin = true,
                                lintFormats = { "%f:%l:%c: %t: %m", "%f:%l: %t: %m" },
                                rootMarkers = { "mix.exs", ".credo.exs" },
                            },
                        },
                    },
                    debuggers = {
                        ["elixir-ls"] = { mason = "elixir-ls", bin = "elixir-ls-debugger" },
                    },
                    defaults = { formatter = false, linter = false, debugger = "elixir-ls" },
                },
            },

            -- Nerd Font icons (statusline / picker rows).
            icons = {
                statusline = "", -- nf-seti-elixir
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

## Triad — lvim-build + lvim-test

The Elixir language surface spans three plugins (each independent, kept consistent):

- **lvim-lang** (this provider) — LSP, toolchain, `:LvimLang` commands, DAP.
- **lvim-build** — the `elixir` recipe (`mix.exs`): `mix compile` / `mix run` / `mix test` /
  `mix format` / `mix credo` through `:LvimBuild`.
- **lvim-test** — the `elixir` (ExUnit) adapter: discovers `test` / `describe` blocks and runs them
  as `mix test file:line`, with the summary tree, signs and diagnostics.

ExUnit has no built-in machine-readable per-test protocol, so lvim-test parses the run output at the
end: failure blocks (`N) test … (Module)` + location) map onto positions, and the `N tests, M
failures` summary confirms the rest passed. Precise **skipped / excluded** per-test mapping would need
a custom ExUnit formatter — a known limitation.
