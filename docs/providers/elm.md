# Elm

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.elm`). `elm-language-server` is the LSP; `elm-format` is the formatter. `elm make` builds; `elm-test` tests. Elm targets JavaScript, so no native debugger.

## LSP

`elm-language-server`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `elm` | elm-format (mason) | — | — | formatter=elm-format |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `elm make src/Main.elm` |
| `:LvimLang test` | `elm-test` |
