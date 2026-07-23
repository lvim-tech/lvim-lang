# Nushell

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.nushell`). Nushell ships its own language server (`nu --lsp`) — no mason; `nu` is resolved through the toolchain. `nu` runs a script.

## LSP

`nushell` — `nu --lsp` (from the Nushell binary; no mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `nu` | — | — | — | — |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang run` | `nu <file>` |


## Notes

Nushell has no external formatter/linter/debugger.