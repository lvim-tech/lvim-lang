# Unison provider

The Unison provider owns Unison tooling through `lvim-lang`. Unison is **unusual**: you don't work
against plain files compiled by a toolchain — you work against a **codebase** (a content-addressed
database) through a running **UCM** (the Unison Codebase Manager, the `ucm` binary). Almost
everything — adding/updating definitions, the type-checker, browsing, running `test` — happens
inside an interactive `ucm` session. This provider is therefore intentionally **lighter and honest**:
it wires the LSP to a running UCM, resolves `ucm`, and exposes only the `ucm` invocations that are
genuinely non-interactive. It does **not** fabricate a build/format/lint/debug flow Unison doesn't
have.

Filetype: `unison`. Project root: `.git` (a Unison codebase usually lives in a git repo).

## The LSP model — a running UCM, not a launched server

There is **no standalone Unison LSP binary**. The language server is served, over **TCP**, by a
**running UCM**:

- Start `ucm` interactively in your codebase (a terminal, `lvim-term`, tmux…). By default it opens
  an LSP server on **`127.0.0.1:5757`**.
- The editor **connects** to that port — the server config (`servers/unison.lua`) uses
  `vim.lsp.rpc.connect(host, port)` as its `cmd` (a TCP transport, not a spawned process). lvim-ls
  passes a non-list `cmd` straight through to `vim.lsp.start`, so the connection is honoured cleanly.

Consequences (and caveats):

- **UCM must already be running** when you open the first Unison buffer. If it isn't, the connection
  fails and lvim-ls latches the server off for that root — **start `ucm`, then re-open the buffer or
  restart the client**. (Auto-retry when UCM comes up later is an OPEN enhancement.)
- The port is configurable. UCM reads the **`UNISON_LSP_PORT`** env var (default `5757`); disable the
  LSP entirely with `UNISON_LSP_ENABLED=false`. If you change UCM's port, set `providers.unison.lsp_port`
  to the **same** value so the editor connects to the right place.
- No mason package is involved — the LSP is UCM's, not an installable server.

## Toolchain

Only one tool, resolved per project root (nothing is installed here):

- **`ucm`** — an explicit `ucm_path` → a `ucm_lookup_cmd` (its first output line) → `PATH`.

Install Unison (UCM) yourself (see the Unison docs). `:checkhealth lvim-lang` reports whether `ucm`
resolves and reminds you the LSP needs a running UCM.

## Commands

`:LvimLang <sub> [args]` in a Unison buffer. The surface is deliberately thin — only `ucm`'s
non-interactive invocations:

| Command | Description |
| --- | --- |
| `:LvimLang run <main>` | `ucm run <main>` — execute a `'{IO, Exception} ()` main from the codebase, non-interactively |
| `:LvimLang run-file [main]` | `ucm run.file <current .u file> [main]` — type-check the scratch file and run its `main` (default `main`) |
| `:LvimLang transcript [file.md]` | `ucm transcript <file.md>` — run a transcript (scripted/CI escape hatch; defaults to the current `.md` buffer) |

Runs go through **lvim-tasks** (panel / history / dock). Unison diagnostics come from the LSP (the
running UCM), so no problem matcher is wired.

## Tests

Unison tests are `test`-typed watch expressions / test terms living **in the codebase namespace**,
not file-and-line facts in a source tree. You run them with the **`test`** command **inside an
interactive UCM session**, or non-interactively by running a **transcript** that contains a `test`
block, e.g. `ci.md`:

    ```ucm
    myproject/main> test
    ```

then `:LvimLang transcript ci.md`. There is **no** first-class `ucm test` shell subcommand, so this
provider ships **no** `:LvimLang test` and **no** `lvim-test` adapter — a treesitter file/line
adapter cannot honestly model namespace-scoped watch-expression tests. Use `transcript` for scripted
test runs. (A dedicated test runner is tracked as an OPEN enhancement.)

## What is intentionally NOT provided (and why)

- **Formatter / linter** — none standard. UCM's type-checker and `update` own validation and
  canonical rendering inside the codebase; there is no external `unison` formatter/linter to wire.
- **DAP / debugging** — Unison has no debug-adapter story. (OPEN.)
- **`lvim-build` recipe** — Unison has no working-directory project manifest (`Cargo.toml`-style) to
  detect; the codebase is a database and operations are name/namespace-based inside UCM. A
  marker-based build recipe would be fabricated, so none is registered — the `run` / `transcript`
  commands cover the real non-interactive invocations instead.

## Configuration

The complete default `providers.unison` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        unison = {
            -- Toolchain (explicit path wins over resolution).
            ucm_path = nil,
            ucm_lookup_cmd = nil, -- shell command whose first line is the `ucm` path

            -- The TCP endpoint the editor connects to for the LSP (where a running UCM serves it).
            -- lsp_port MUST match UCM's port (default 5757; keep in sync with UNISON_LSP_PORT).
            lsp_host = "127.0.0.1",
            lsp_port = 5757,

            -- LSP server catalog. The single "unison" server has NO mason package — it is served by a
            -- running UCM over TCP (servers/unison.lua uses a TCP-connect cmd).
            lsp = {
                servers = {
                    unison = {
                        mason = nil, -- served by UCM, not an installable binary
                        filetypes = { "unison" },
                        role = "types",
                        settings = {},
                    },
                },
                default = "unison",
            },

            -- Per-filetype catalog. Empty on purpose: Unison has no standard external
            -- formatter / linter / debugger (UCM owns validation inside the codebase).
            ft = {
                unison = { defaults = {} },
            },

            -- Statusline / picker icons (Nerd Font).
            icons = {
                statusline = "󰊕",
                run = "󰐊",
                transcript = "󰈙",
                repl = "󰆍",
            },
        },
    },
})
```
