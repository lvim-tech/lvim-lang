# OCaml provider

The OCaml provider owns OCaml tooling through `lvim-lang`: **ocaml-lsp** (binary `ocamllsp`, the
LSP), `dune` build / exec / test / utop / fmt through **lvim-tasks**, **opam** dependency operations,
and **earlybird** bytecode debugging through **lvim-dap**. Everything is resolved per project and
lazy — nothing is wired until the first OCaml buffer is opened.

Filetypes: `ocaml`, `ocaml.interface` (`.mli`), `ocamllex`, `menhir`, `dune`. Project root:
`dune-project` → `.git`.

## Toolchain

Resolved per project root through **opam** (the OCaml package manager — a project-local `_opam/`
switch wins over the global one), then PATH:

- **`ocaml`** — explicit path → lookup cmd → active opam switch (`opam var bin`) → PATH.
- **`dune`** — explicit path → opam switch → PATH.
- **`ocaml-lsp`** (`ocamllsp`) — explicit path → opam switch → the mason bin → PATH.
- **`ocamlformat`** — explicit path → opam switch → the mason bin → PATH.
- **`opam`** — PATH (used for dependency commands + health).

Nothing is installed here. OCaml, dune, ocaml-lsp-server and ocamlformat are the user's own opam
tools (`opam switch create`, `opam install …`); ocaml-lsp-server / ocamlformat may also come from the
mason registry through the installer.

## Auto-install (the file-open popup)

Opening an OCaml file offers the **active** tools it needs but lacks, through the unified
`lvim-installer` popup: ocaml-lsp-server (LSP) and the chosen debugger (**ocamlearlybird**). The
OCaml compiler + dune are the user's own opam toolchain and are not offered — a missing one is
surfaced as a requirement warning with an `opam` hint.

## LSP server catalog

ocaml-lsp is the default (and only) server. It is configured through **initializationOptions**
(codelens / extended hover / inlay hints / dune diagnostics), not workspace settings. ocaml-lsp
formats OCaml natively via **ocamlformat** (exactly as rust-analyzer drives rustfmt), so the default
formatter and linter are `false` — the catalog still OFFERS ocamlformat via efm.

| Server | Role | Filetypes |
| --- | --- | --- |
| `ocaml-lsp` (default) | types / hover / definition / rename / inlay hints / format | ocaml, ocaml.interface, ocamllex, menhir, dune |

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `ocaml` | ocamlformat (efm, `.ocamlformat`) | — | ocamlearlybird | formatter=false, linter=false, debugger=ocamlearlybird |
| `ocaml.interface` | ocamlformat (efm, `.ocamlformat`) | — | — | formatter=false, linter=false |
| `ocamllex` / `menhir` / `dune` | — | — | — | — |

The ocamlformat efm entry is gated on a `.ocamlformat` marker (ocamlformat requires one); ocaml-lsp
formats natively by default, so selecting the efm formatter is opt-in
(`ft.ocaml.formatter = "ocamlformat"`).

## Commands

`:LvimLang <sub> [args]` in an OCaml buffer:

| Command | Description |
| --- | --- |
| `:LvimLang build [args]` | `dune build` |
| `:LvimLang run [args]` | `dune exec <target>` (applies the active run config) |
| `:LvimLang exec <target> [-- args]` | `dune exec <target>` (raw, no run config) |
| `:LvimLang test [args]` | `dune test` (alias of `dune runtest`) |
| `:LvimLang test-func` | run the test directory of the file under the cursor (`dune runtest <dir>`) |
| `:LvimLang fmt [args]` | `dune build @fmt --auto-promote` (ocamlformat) |
| `:LvimLang utop [dir]` | `dune utop` — a REPL with the project's libraries |
| `:LvimLang deps <install\|list\|upgrade>` | opam dependency operations |
| `:LvimLang debug` | start / continue an earlybird session |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

**Dependencies:** an OCaml project declares its dependencies in `dune-project` (the `(depends …)` of
a `(package …)` stanza) and/or a generated `<name>.opam` — so **adding / removing a dependency means
editing those files by hand**; `:LvimLang deps` exposes only the safe opam operations (`install` the
declared deps, `list` the switch, `upgrade`).

**Testing / test-func:** dune has no per-test name filter (unlike `cargo test <name>`), so
`test-func` runs the whole test **directory** of the file under the cursor — the finest scope dune
supports. Richer per-test discovery lives in the `lvim-test` OCaml adapter.

**Debugging:** earlybird (`ocamlearlybird`) debugs **bytecode** executables — build with `dune build`
so the `.bc` target exists, then `:LvimLang debug` prompts for the bytecode under `_build/default/`.

## Run configurations

Named configs in `.lvim/lang/run.lua`. `:LvimLang config` picks the active one; `:LvimLang run`
applies its dune flags / target / args / env.

```lua
return {
    {
        name = "main",
        dune_flags = {}, -- extra `dune exec` flags
        target = "bin/main.exe", -- the executable target for `dune exec`
        args = { "--verbose" }, -- program arguments (after --)
        env = { OCAMLRUNPARAM = "b" },
    },
    { name = "cli", target = "bin/cli.exe" },
}
```

## Configuration

The complete default `providers.ocaml` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        ocaml = {
            -- Toolchain (explicit paths win over resolution).
            ocaml_path = nil,
            dune_path = nil,
            ocaml_lsp_path = nil, -- the `ocamllsp` binary
            ocamlformat_path = nil,
            earlybird_path = nil, -- the `ocamlearlybird` debug adapter
            ocaml_lookup_cmd = nil, -- shell command whose first line is the `ocaml` path
            version_manager = nil, -- "opam" | false | function(root, tool); default: active opam switch → PATH

            -- The dune build directory NAME (used to default the debugger's bytecode prompt).
            build_dir = "_build",

            -- LSP server catalog + selection.
            lsp = {
                servers = {
                    ["ocaml-lsp"] = {
                        mason = "ocaml-lsp-server",
                        bin = "ocamllsp",
                        filetypes = { "ocaml", "ocaml.interface", "ocamllex", "menhir", "dune" },
                        role = "types",
                        -- ocaml-lsp initializationOptions (not workspace settings).
                        init_options = {
                            codelens = { enable = true },
                            extendedHover = { enable = true },
                            inlayHints = { hintPatternVariables = false, hintLetBindings = false },
                            duneDiagnostics = { enable = true },
                            syntaxDocumentation = { enable = true },
                        },
                        settings = {},
                    },
                },
                default = "ocaml-lsp", -- string | string[]
            },

            -- Per-filetype formatter / linter / debugger catalog + selection.
            ft = {
                ocaml = {
                    formatters = {
                        ocamlformat = {
                            mason = "ocamlformat",
                            efm = {
                                formatCommand = "ocamlformat --name ${INPUT} -",
                                formatStdin = true,
                                rootMarkers = { ".ocamlformat" },
                            },
                        },
                    },
                    linters = {},
                    debuggers = {
                        ocamlearlybird = { mason = "ocamlearlybird" },
                    },
                    -- ocaml-lsp formats via ocamlformat natively, so the defaults are false.
                    defaults = { formatter = false, linter = false, debugger = "ocamlearlybird" },
                },
                ["ocaml.interface"] = {
                    formatters = {
                        ocamlformat = {
                            mason = "ocamlformat",
                            efm = {
                                formatCommand = "ocamlformat --name ${INPUT} -",
                                formatStdin = true,
                                rootMarkers = { ".ocamlformat" },
                            },
                        },
                    },
                    linters = {},
                    defaults = { formatter = false, linter = false },
                },
                ocamllex = { defaults = {} },
                menhir = { defaults = {} },
                dune = { defaults = {} },
            },

            -- Icons (Nerd Font).
            icons = {
                statusline = "", -- nf-seti-ocaml
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

## Available OCaml packages (mason registry)

| Category | In the catalog | Also in the registry / opam |
| --- | --- | --- |
| LSP | ocaml-lsp-server (`ocamllsp`) | — |
| Formatter | ocamlformat (efm) | ocamlformat (opam) |
| Linter | — | — |
| DAP | ocamlearlybird | ocamlearlybird (opam) |
| Toolchain | — | ocaml, dune, opam (the user's own) |
