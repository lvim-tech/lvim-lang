# R

A declarative Tier 2 provider. `r-languageserver` is the default LSP (it formats via styler and lints
via lintr natively); `air` is offered as a fast formatter AND an alternative server. Filetypes `r`,
`rmd`. mason ships no R debug adapter (R debugs via `browser()`), so no debugger is offered.

## LSP

`r-languageserver` (default) · `air` (opt-in: `lsp.server = "air"`).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `r` | air | — | — | formatter=false (LSP owns) |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang run` | `Rscript <file>` |
| `:LvimLang test` | `devtools::test()` |
