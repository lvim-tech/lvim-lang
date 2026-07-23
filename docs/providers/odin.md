# Odin

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.odin`). `ols` (Odin Language Server) is the LSP and formats natively. `odin build/run/test`.

## LSP

`ols` (formats natively).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `odin` | — (ols) | — | codelldb | formatter=false, debugger=codelldb |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `odin build .` |
| `:LvimLang run` | `odin run .` |
| `:LvimLang test` | `odin test .` |

## Debugging

Native via codelldb — Odin compiles to native binaries.
