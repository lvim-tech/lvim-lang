# ReScript

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.rescript`). `rescript-language-server` is the LSP; `rescript format` formats natively. `rescript build` compiles.

## LSP

`rescript-language-server` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `rescript` | rescript-format | — | — | opt-in |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `rescript build` |
| `:LvimLang run` | `rescript build -w` (watch) |


## Notes

ReScript compiles to JavaScript; no native debugger.