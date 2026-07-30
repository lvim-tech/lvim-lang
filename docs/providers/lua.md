# Lua

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.lua`). `lua-language-server`
is the LSP; the catalog offers every mason Lua tool so you pick your default.

## LSP

`lua-language-server` (default; diagnostics with `vim` global, inlay hints).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `lua` | stylua, luaformatter, emmylua-codeformat | luacheck, selene | local-lua-debugger-vscode | formatter=stylua, linter=false, debugger=false |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang run` | run the file — `nvim -l <file>` for Neovim Lua, else `lua <file>` |
| `:LvimLang test` | `busted` (installed on demand) |

### `run` refuses the editor's own configuration

A file under `stdpath("config")` is not run at all — `run` explains why instead. Nothing there is a
standalone script: every file is a module the editor itself loads, so a separate process is never what
you mean. `nvim -l init.lua` exits 0 having loaded the **whole config a second time**, writing to state
it shares with the running editor (the session / control-center databases, the active theme, the
keys-helper cache) — a concurrent-write hazard, not a dry run; every other file there is a module that
expects to be `require`d and exits 1. Use `:source %` to apply a config file in the running editor, or
restart.

Plugin modules on the `runtimepath` are deliberately still run: they exit 1 with Neovim's own clear
error, they touch nothing, and a plugin repo legitimately holds real scripts worth running.

### Which interpreter `run` uses

A Lua file here is one of two languages sharing a syntax: a plain script, which the standalone
interpreter runs, and **Neovim Lua**, which only means anything inside Neovim (it reads the `vim`
global) — handing that to `lua` fails on its first line with
`attempt to index a nil value (global 'vim')`. So `run` picks the interpreter from the file:

- **Neovim Lua** → `nvim -l <file>` (Neovim's script mode: the full API, without loading your config).
  A file counts as Neovim Lua when it lives under a `runtimepath` entry — your config, the data dir,
  any installed plugin — or when its first 200 lines reference the `vim` global (which catches Neovim
  Lua outside the runtimepath, such as a project's `.lvim/` config or a scratch script).
- **anything else** → the Lua interpreter resolved through the toolchain (`lua` / `luajit` on PATH).

## Debugging

- **nlua / osv** — debug a RUNNING Neovim's Lua: start the server with
  `:lua require('osv').launch({ port = 8086 })`, then attach.
- **local-lua** — launch a plain Lua script through the mason `local-lua-debugger-vscode` adapter.
