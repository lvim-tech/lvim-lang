# Zig provider

The Zig provider owns Zig tooling through `lvim-lang`: **zls** (LSP), `zig` build / run / test / fmt
and package commands through **lvim-tasks**, and **lldb-dap** debugging through **lvim-dap**.
Everything is resolved per project and lazy — nothing is wired until the first Zig buffer is opened.

Zig ships as ONE self-contained binary: `zig` is the compiler, the build system (`zig build`), the
test runner (`zig test` / `zig build test`) AND the formatter (`zig fmt` — a subcommand, not a
separate tool). Only **zls** (the language server) and **lldb-dap** (the debug adapter) are mason
packages; the Zig toolchain itself is the user's own.

Filetypes: `zig`, `zir`. Project root: `build.zig` → `build.zig.zon` → `.git`.

## Toolchain

Resolved per project root through the version manager (mise / asdf, which honour a project's
`.tool-versions` / `mise.toml`), then PATH:

- **`zig`** — explicit `zig_path` → `zig_lookup_cmd` → `mise/asdf which zig` → PATH.
- **`zls`** — explicit `zls_path` → the mason bin → PATH.
- **`lldb-dap`** — explicit `lldb_dap_path` → the mason bin → PATH.

Nothing is installed here. `zig fmt` uses the resolved `zig`; zls resolves the standard library,
builds on save, formats and produces diagnostics through the same `zig` — so the server config
passes the per-root `zig` to zls via `zig_exe_path` (unless you set it explicitly).

## Auto-install (the file-open popup)

Opening a Zig file offers the **active** tools it needs but lacks, through the unified
`lvim-installer` popup: zls (LSP) and the chosen debugger (**lldb-dap**). The Zig toolchain is not a
mason package and is not offered — install it from https://ziglang.org/download (or via mise / asdf).

## LSP server catalog

zls is the single server. It formats Zig natively (it invokes `zig fmt`) and surfaces compile
diagnostics, so the default formatter and linter are `false`.

| Server | Role | Filetypes |
| --- | --- | --- |
| `zls` (default) | types / hover / definition / rename / inlay hints / format | zig |

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `zig` | zig-fmt (efm, `zig fmt --stdin`) | — | lldb-dap, codelldb | formatter=false, linter=false, debugger=lldb-dap |

## Commands

`:LvimLang <sub> [args]` in a Zig buffer. Every command adapts to the project shape (a `build.zig`
project vs a single file):

| Command | Description |
| --- | --- |
| `:LvimLang build [args]` | `zig build` (project) / `zig build-exe <file>` (single file) |
| `:LvimLang run [args]` | `zig build run` / `zig run <file>` (applies the active run config) |
| `:LvimLang test [args]` | `zig build test` / `zig test <file>` |
| `:LvimLang test-func` | run the `test` block under the cursor (`--test-filter <name>`) |
| `:LvimLang fmt [path]` | `zig fmt` — the formatter built into the `zig` binary |
| `:LvimLang fetch <url\|path>` | `zig fetch --save` — add a dependency to `build.zig.zon` |
| `:LvimLang deps <fetch>` | `zig build --fetch` — prefetch declared dependencies |
| `:LvimLang debug` | start / continue an lldb-dap / codelldb session |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

## Run configurations

Named configs in `.lvim/lang/run.lua`. `:LvimLang config` picks the active one; `:LvimLang run`
applies its zig flags / args / env.

```lua
return {
    {
        name = "release",
        zig_flags = { "-Doptimize=ReleaseFast" }, -- extra `zig build run` / `zig run` flags
        args = { "--verbose" }, -- program arguments (after --)
        env = { ZIG_DEBUG_COLOR = "on" },
    },
    { name = "dev" },
}
```

## Debugging

Zig produces native binaries with DWARF debug info (`zig build` → `zig-out/bin/`), debugged with
LLVM's **lldb-dap** adapter (the catalog default; **codelldb** is offered as an alternative). The
launch config prompts for the executable, defaulting under the project's `bin_dir`
(`zig-out/bin`). `:LvimLang debug` starts / continues a session.

## Configuration

The complete default `providers.zig` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        zig = {
            -- Toolchain (explicit paths win over resolution).
            zig_path = nil,
            zls_path = nil,
            lldb_dap_path = nil,
            codelldb_path = nil,
            zig_lookup_cmd = nil, -- shell command whose first line is the `zig` path
            version_manager = nil, -- "mise" | "asdf" | false | function(root); default: mise→asdf→PATH

            -- The Zig build output dir (where `zig build` drops binaries) — defaults the debug prompt.
            bin_dir = "zig-out/bin",

            -- LSP server catalog + selection.
            lsp = {
                servers = {
                    zls = {
                        mason = "zls",
                        filetypes = { "zig" },
                        role = "types",
                        settings = {
                            zls = {
                                enable_build_on_save = true,
                                semantic_tokens = "full",
                                inlay_hints_show_parameter_name = true,
                                inlay_hints_show_builtin = true,
                                warn_style = true,
                            },
                        },
                    },
                },
                default = "zls", -- string | string[]
            },

            -- Per-filetype formatter / linter / debugger catalog + selection.
            ft = {
                zig = {
                    formatters = {
                        ["zig-fmt"] = { efm = { formatCommand = "zig fmt --stdin", formatStdin = true } },
                    },
                    linters = {},
                    debuggers = {
                        ["lldb-dap"] = { mason = "lldb-dap" },
                        codelldb = { mason = "codelldb" },
                    },
                    -- zls formats (via `zig fmt`) and lints (compile diagnostics), so the defaults are false.
                    defaults = { formatter = false, linter = false, debugger = "lldb-dap" },
                },
            },

            -- Icons (Nerd Font).
            icons = {
                statusline = "",
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

## Available Zig packages (mason registry)

| Category | In the catalog | Also in the registry / toolchain |
| --- | --- | --- |
| LSP | zls | — |
| Formatter | zig fmt (toolchain) | — |
| Linter | — (zls compile diagnostics) | — |
| DAP | lldb-dap, codelldb | — |
