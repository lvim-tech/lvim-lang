# Crystal

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.crystal`). `crystalline` is the LSP; `crystal tool format` formats natively. `shards` builds; `crystal spec` tests.

## LSP

`crystalline`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `crystal` | crystal tool format (efm) | — | codelldb, lldb-dap | formatter=crystal-format, debugger=codelldb |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `shards build` |
| `:LvimLang run` | `crystal run <file>` |
| `:LvimLang test` | `crystal spec` |

## Debugging

Native (DWARF) via codelldb / lldb-dap — Crystal compiles to native binaries.
