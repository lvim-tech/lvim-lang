# Rust provider

The Rust provider owns Rust tooling through `lvim-lang`: **rust-analyzer** (LSP), `cargo`
build / run / test / check / clippy / fmt and dependency commands through **lvim-tasks**, macro
expansion (**cargo-expand**), and **CodeLLDB** debugging through **lvim-dap**. Everything is
resolved per project and lazy — nothing is wired until the first Rust buffer is opened.

Filetype: `rust`. Project root: `Cargo.toml` → `Cargo.lock` → `.git`.

## Toolchain

Resolved per project root through **rustup** (which honours a project's `rust-toolchain.toml`),
then mise / asdf, then PATH:

- **`cargo`** / **`rustc`** — explicit path → lookup cmd → `rustup which` → PATH.
- **`rust-analyzer`** — explicit path → `rustup which` → the mason bin → PATH.
- **`rustfmt`** / **`clippy`** — rustup components (`rustup which`) → PATH.

Nothing is installed here. `rustfmt` and `clippy` ship with the toolchain (`rustup component add
…`); rust-analyzer is a rustup component OR a mason package. On a machine where only a rustup proxy
is present (component not installed), health reports it as "resolved but not runnable".

## Auto-install (the file-open popup)

Opening a Rust file offers the **active** tools it needs but lacks, through the unified
`lvim-installer` popup: rust-analyzer (LSP) and the chosen debugger (**codelldb**). `rustfmt` /
`clippy` are toolchain components (not mason) and are not offered. cargo-expand / cargo-nextest are
`cargo install` tools — checked on PATH with a hint, not auto-installed.

## LSP server catalog

rust-analyzer is the default. `lsp.default` may be a string or a list (add `bacon-ls` for
background-check diagnostics alongside RA). rust-analyzer formats Rust natively (via rustfmt) and
drives clippy (`checkOnSave`), so the default formatter and linter are `false`.

| Server | Role | Filetypes |
| --- | --- | --- |
| `rust-analyzer` (default) | types / hover / definition / rename / inlay hints / format / clippy | rust |
| `bacon-ls` | background `bacon` diagnostics | rust |

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `rust` | rustfmt (efm, toolchain) | bacon | codelldb, cpptools | formatter=false, linter=false, debugger=codelldb |

## Commands

`:LvimLang <sub> [args]` in a Rust buffer:

| Command | Description |
| --- | --- |
| `:LvimLang build [args]` | `cargo build` |
| `:LvimLang run [args]` | `cargo run` (applies the active run config) |
| `:LvimLang test [args]` | `cargo test` |
| `:LvimLang test-func` | run the `#[test]` function under the cursor (`cargo test <name>`) |
| `:LvimLang nextest [args]` | `cargo nextest run` (the faster runner; on-demand) |
| `:LvimLang check [args]` | `cargo check` |
| `:LvimLang clippy [args]` | `cargo clippy --all-targets` |
| `:LvimLang fmt [args]` | `cargo fmt` |
| `:LvimLang expand [item]` | `cargo expand` macros into a scratch buffer |
| `:LvimLang add <crate[@version]> [--features …]` | `cargo add` |
| `:LvimLang remove <crate…>` | `cargo remove` |
| `:LvimLang update [crate]` | `cargo update` |
| `:LvimLang deps <update\|tree\|fetch>` | cargo dependency commands |
| `:LvimLang debug` | start / continue a CodeLLDB session |
| `:LvimLang debug-test` | build + debug the test under the cursor (`--exact <name>`) |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

## Run configurations

Named configs in `.lvim/lang/run.lua`. `:LvimLang config` picks the active one; `:LvimLang run`
applies its cargo flags / features / bin / args / env.

```lua
return {
    {
        name = "release",
        cargo_flags = { "--release" }, -- extra `cargo run` flags
        features = { "foo", "bar" }, -- --features foo,bar
        bin = "myapp", -- --bin myapp (a specific binary target)
        args = { "--verbose" }, -- program arguments (after --)
        env = { RUST_LOG = "debug" },
    },
    { name = "dev" },
}
```

## Configuration

The complete default `providers.rust` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        rust = {
            -- Toolchain (explicit paths win over resolution).
            cargo_path = nil,
            rustc_path = nil,
            rust_analyzer_path = nil,
            cargo_lookup_cmd = nil, -- shell command whose first line is the `cargo` path
            version_manager = nil, -- "rustup" | "mise" | "asdf" | false | function(root, tool); default: rustup→mise→asdf→PATH

            -- LSP server catalog + selection.
            lsp = {
                servers = {
                    ["rust-analyzer"] = {
                        mason = "rust-analyzer",
                        filetypes = { "rust" },
                        role = "types",
                        settings = {
                            ["rust-analyzer"] = {
                                cargo = { allFeatures = true, buildScripts = { enable = true } },
                                checkOnSave = true,
                                check = { command = "clippy" },
                                procMacro = { enable = true },
                                inlayHints = {
                                    bindingModeHints = { enable = false },
                                    closureReturnTypeHints = { enable = "never" },
                                    lifetimeElisionHints = { enable = "never" },
                                },
                                diagnostics = { enable = true, experimental = { enable = true } },
                                lens = { enable = true },
                            },
                        },
                    },
                    ["bacon-ls"] = {
                        mason = "bacon-ls",
                        filetypes = { "rust" },
                        role = "diagnostics",
                        settings = {},
                    },
                },
                default = "rust-analyzer", -- string | string[]
            },

            -- Per-filetype formatter / linter / debugger catalog + selection.
            ft = {
                rust = {
                    formatters = {
                        rustfmt = {
                            efm = { formatCommand = "rustfmt --emit stdout --edition 2021", formatStdin = true },
                        },
                    },
                    linters = {
                        bacon = { mason = "bacon", efm = { lintCommand = "bacon --headless", lintStdin = false } },
                    },
                    debuggers = {
                        codelldb = { mason = "codelldb" },
                        cpptools = { mason = "cpptools", bin = "OpenDebugAD7" },
                    },
                    -- rust-analyzer formats (rustfmt) and drives clippy, so the defaults are false.
                    defaults = { formatter = false, linter = false, debugger = "codelldb" },
                },
            },

            -- Icons (Nerd Font).
            icons = {
                statusline = "󱘗",
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

## Available Rust packages (mason registry)

| Category | In the catalog | Also in the registry / toolchain |
| --- | --- | --- |
| LSP | rust-analyzer, bacon-ls | — |
| Formatter | rustfmt (toolchain) | — |
| Linter | bacon, clippy (toolchain) | — |
| DAP | codelldb, cpptools | — |
| Helpers | — | cargo-expand, cargo-nextest (`cargo install`) |
