# Ada

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.ada`). `ada-language-server` is the LSP. `gprbuild` builds; `gnattest` scaffolds/runs the test harness.

## LSP

`ada-language-server` (formats via gnatpp).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `ada` | — (gnatpp via LSP) | — | codelldb | formatter=false, debugger=codelldb |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `gprbuild` |
| `:LvimLang test` | `gnattest` |

## Debugging

Native via codelldb / gdb — Ada compiles to native binaries.
