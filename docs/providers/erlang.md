# Erlang provider

The Erlang provider owns Erlang tooling through `lvim-lang`: **erlang_ls** (LSP), the **rebar3**
build tool (compile / shell / eunit / ct and dependency commands) through **lvim-tasks**, **EUnit** /
**Common Test** test running, and **erlfmt** formatting (through efm, and `:LvimLang fmt`). Everything
is resolved per project and lazy — nothing is wired until the first Erlang buffer is opened.

Filetype: `erlang`. Project root: `rebar.config` → `erlang.mk` → `.git`.

## Toolchain

Erlang/OTP is the user's **own** runtime, usually managed by a version manager and pinned per project
by `.tool-versions`. Resolved per project root:

- **`erl`** — explicit `erl_path` → lookup cmd → version manager → PATH. The version manager tries
  **mise**, then **asdf** (each `<mgr> which erl`, run in the project so `.tool-versions` wins).
  **kerl**-managed installs are found on PATH (kerl is a shell installer with no resolver CLI).
- **`rebar3`** — explicit `rebar3_path` → the project-vendored escript (`<root>/rebar3`) → PATH.
- **`erlang_ls`** / **`erlfmt`** — mason packages (`erlang-ls` / `erlfmt`): explicit path → the mason
  bin → PATH. (The `erlang-ls` mason package installs the binary as `erlang_ls`.)

Nothing is installed here. Erlang and rebar3 are the user's own; a missing one is surfaced at
activation and in `:checkhealth` with an install hint. `erl` has no `--version` flag, so its OTP
release is read out of the emulator (`erlang:system_info(otp_release)`).

## Auto-install (the file-open popup)

Opening an Erlang file offers the **active** tools it needs but lacks, through the unified
`lvim-installer` popup: erlang-ls (LSP) and **erlfmt** (the default formatter). Erlang and rebar3 are
the user's own runtime and are **not** offered.

## LSP server catalog

erlang_ls is the single Erlang server (mason package `erlang-ls`, binary `erlang_ls`). It is
configured through an `erlang_ls.config` file at the project root (not over the protocol), so
`settings` is empty by default. erlang_ls does **not** format Erlang, so the per-filetype formatter
defaults to **erlfmt**; `catalog.lsp_on_attach` switches the LSP's formatting capability off on attach
so the two never both format the buffer. erlang_ls provides diagnostics (compiler + dialyzer), so the
efm linter defaults to `false`.

| Server | Role | Filetypes |
| --- | --- | --- |
| `erlang-ls` (default) | completion / hover / definition / references / diagnostics | erlang |

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `erlang` | erlfmt (efm) | — | — | formatter=erlfmt, linter=false, debugger=false |

## Commands

`:LvimLang <sub> [args]` in an Erlang buffer:

| Command | Description |
| --- | --- |
| `:LvimLang compile [args]` | `rebar3 compile` |
| `:LvimLang shell [args]` | `rebar3 shell` (applies the active run config) |
| `:LvimLang eunit [args]` | `rebar3 eunit` — the whole project |
| `:LvimLang ct [args]` | `rebar3 ct` — the whole project |
| `:LvimLang test-func` | run the EUnit test function under the cursor (`--test=<module>:<function>`) |
| `:LvimLang test-file` | run every EUnit test in the current module (`--module=<module>`) |
| `:LvimLang ct-suite` | run the current Common Test suite (`*_SUITE.erl`, `--suite=<module>`) |
| `:LvimLang fmt [args]` | `erlfmt --write <current file>` |
| `:LvimLang deps <get\|upgrade\|tree>` | rebar3 dependency commands |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

## Testing

EUnit test functions are named `*_test` (a simple test) or `*_test_` (a test **generator**). The test
under the cursor is found with treesitter (the enclosing `fun_decl` clause name) and run with
`rebar3 eunit --test=<module>:<function>`; the whole module runs with `--module=<module>`, and Common
Test suites with `rebar3 ct --suite=<module>`. The `lvim-test` Erlang adapter discovers the same
`*_test` / `*_test_` functions and maps EUnit's verbose output back onto them by name.

## Debugging

**Not supported.** Erlang has no reliable mason debug adapter, and erlang_ls' own debugging support is
limited, so the provider declares **no debugger** — there are no `debug` commands. Debugging Erlang is
done with the OTP tools (`dbg`, `redbug`, the `debugger` GUI, or `rebar3 shell`). (OPEN: revisit if a
first-class Erlang DAP adapter becomes available in the mason registry.)

## Run configurations

Named configs in `.lvim/lang/run.lua`. `:LvimLang config` picks the active one; `:LvimLang shell`
applies its apps / eval / args / env.

```lua
return {
    {
        name = "app",
        apps = { "myapp", "otherapp" }, -- rebar3 shell --apps myapp,otherapp
        eval = "application:ensure_all_started(myapp).", -- rebar3 shell --eval "…"
        args = { "--sname", "dev" }, -- extra `rebar3 shell` args
        env = { ERL_FLAGS = "-kernel shell_history enabled" },
    },
    { name = "default" },
}
```

## Configuration

The complete default `providers.erlang` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        erlang = {
            -- Toolchain (explicit paths win over resolution).
            erl_path = nil,
            rebar3_path = nil,
            erlang_ls_path = nil,
            erlfmt_path = nil,
            erl_lookup_cmd = nil, -- shell command whose first line is the `erl` path
            version_manager = nil, -- "mise"|"asdf"|false|function(root); default: mise→asdf→PATH (kerl via PATH)

            -- LSP server catalog + selection.
            lsp = {
                servers = {
                    ["erlang-ls"] = {
                        mason = "erlang-ls",
                        bin = "erlang_ls", -- the installed binary name differs from the mason package
                        filetypes = { "erlang" },
                        role = "types",
                        settings = {}, -- erlang_ls is configured via a project erlang_ls.config file
                    },
                },
                default = "erlang-ls", -- string | string[]
            },

            -- Per-filetype formatter / linter / debugger catalog + selection.
            ft = {
                erlang = {
                    formatters = {
                        erlfmt = { mason = "erlfmt", efm = { formatCommand = "erlfmt -", formatStdin = true } },
                    },
                    linters = {},
                    debuggers = {},
                    -- erlang_ls does not format Erlang, so erlfmt is the default formatter; it
                    -- provides diagnostics, so the linter is false; no mason debug adapter exists.
                    defaults = { formatter = "erlfmt", linter = false, debugger = false },
                },
            },

            -- Nerd Font icons (statusline / picker rows).
            icons = {
                statusline = "", -- nf-dev-erlang
                test = "󰙨",
                build = "󰜫",
                run = "󰐊",
                deps = "󰏗",
            },
        },
    },
})
```

## Available Erlang packages (mason registry)

| Category | In the catalog | Also in the registry / toolchain |
| --- | --- | --- |
| LSP | erlang-ls | — |
| Formatter | erlfmt (efm) | — |
| Linter | — (erlang_ls diagnostics) | elvis (`elvis_core`, not mason) |
| DAP | — (no reliable adapter) | — |
| Runtime | — | Erlang/OTP + rebar3 (the user's own) |
