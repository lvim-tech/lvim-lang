# Gleam

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.gleam`). Gleam ships its own language server (`gleam lsp`). `gleam format` formats; `gleam build/test`. Targets Erlang/JS, so no native debugger.

## LSP

`gleam lsp` (built-in; no mason — `gleam` from the toolchain).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `gleam` | gleam format (efm) | — | — | formatter=false (LSP) |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `gleam build` |
| `:LvimLang run` | `gleam run` |
| `:LvimLang test` | `gleam test` (gleeunit) |
