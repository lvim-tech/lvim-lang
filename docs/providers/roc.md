# Roc

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.roc`). `roc_language_server` is the LSP; `roc format` formats natively. `roc build` / `roc dev` (run) / `roc test`.

## LSP

`roc_language_server` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `roc` | roc-format | — | — | opt-in |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `roc build <file>` |
| `:LvimLang run` | `roc dev <file>` |
| `:LvimLang test` | `roc test <file>` |


## Notes

Roc is experimental; debugging support is nascent, so no debugger is offered yet.