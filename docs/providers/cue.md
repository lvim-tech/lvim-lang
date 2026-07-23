# CUE

A declarative Tier 3 provider (config / DSL) — data record in `lvim-lang.providers.registry.cue`. cuelsp is the LSP; `cue fmt` formats; `cue vet` validates.

## LSP

`cuelsp` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `cue` | cue fmt | — | opt-in |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang vet` | `cue vet` |
| `:LvimLang eval` | `cue eval <file>` |

## Validation

`lvim-build` offers a file-level **validate** action (`cue vet`), shown only when the checker is installed.
