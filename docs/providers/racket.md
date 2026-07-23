# Racket

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.racket`). Install the LSP with `raco pkg install racket-langserver`. `raco fmt` formats; `raco make/test`.

## LSP

`racket-langserver` (a Racket package; `racket -l racket-langserver`).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `racket` | raco fmt (efm) | — | — | formatter=false |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `raco make <file>` |
| `:LvimLang run` | `racket <file>` |
| `:LvimLang test` | `raco test <file>` (rackunit) |
