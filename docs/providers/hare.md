# Hare

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.hare`). `hare-lsp` is the LSP. `hare build/run/test`.

## LSP

`hare-lsp` (from PATH; no mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `hare` | — | — | codelldb | debugger=codelldb |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `hare build` |
| `:LvimLang run` | `hare run <file>` |
| `:LvimLang test` | `hare test` |

## Debugging

Native via codelldb — Hare compiles to native binaries.
