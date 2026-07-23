# PureScript

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.purescript`). `purescript-language-server` is the LSP; `purs-tidy` formats. `spago build/test`. Targets JavaScript, so no native debugger.

## LSP

`purescript-language-server`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `purescript` | purescript-tidy (mason, purs-tidy) | — | — | formatter=purescript-tidy |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `spago build` |
| `:LvimLang test` | `spago test` |
