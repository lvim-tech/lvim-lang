# Nim

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.nim`). `nimlangserver` is the LSP; nph formats (from PATH). `nim c` builds; `nimble test` runs unittest.

## LSP

`nimlangserver`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `nim` | nph (efm, PATH) | — | codelldb | formatter=false, debugger=codelldb |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `nim c <file>` |
| `:LvimLang run` | `nim c -r <file>` |
| `:LvimLang test` | `nimble test` |

## Debugging

Native via codelldb / gdb — Nim compiles to native binaries.
