# Fortran

A declarative Tier 3 provider (scientific / legacy) — data record in `lvim-lang.providers.registry.fortran`. fortls is the LSP; fprettify / findent format. Fortran compiles to a native binary → codelldb debugging. fpm builds/runs/tests.

## LSP

`fortls` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `fortran` | fprettify, findent | — | codelldb | debugger=codelldb |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `fpm build` |
| `:LvimLang run` | `fpm run` |
| `:LvimLang test` | `fpm test` |

## Debugging

Native via **codelldb** (`program = pick`) — Fortran compiles to native binaries.

## Testing

`lvim-test` runs `fpm test` (suite-granular; covered files marked by exit code).
