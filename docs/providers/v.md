# V

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.v`). `v-analyzer` is the LSP; `v fmt` formats. `v build/run/test`.

## LSP

`v-analyzer`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `vlang` | v fmt (efm) | — | codelldb | formatter=v-fmt, debugger=codelldb |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `v .` |
| `:LvimLang run` | `v run <file>` |
| `:LvimLang test` | `v test .` |

## Debugging

Native via codelldb — V compiles to native binaries.
