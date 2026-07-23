# Pascal

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.pascal`). `pasls` (the Pascal Language Server, from PATH — no mason) is the LSP. Pascal compiles to native binaries and debugs with codelldb / gdb. `fpc` compiles a file; `lazbuild` builds a Lazarus project.

## LSP

`pasls` (from PATH; no mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `pascal` | — | — | codelldb | debugger=codelldb |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `fpc <file>` |
| `:LvimLang run` | `fpc <file>` |


## Debugging

Native via codelldb — Pascal compiles to native binaries.