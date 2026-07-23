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
| `:LvimLang run` | `lua <file>` |
| `:LvimLang test` | `busted` (installed on demand) |

## Debugging

- **nlua / osv** — debug a RUNNING Neovim's Lua: start the server with
  `:lua require('osv').launch({ port = 8086 })`, then attach.
- **local-lua** — launch a plain Lua script through the mason `local-lua-debugger-vscode` adapter.
