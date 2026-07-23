# Groovy

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.groovy`). `groovy-language-server` is the LSP; `npm-groovy-lint` formats and lints. Gradle builds/tests; `groovy` runs a script.

## LSP

`groovy-language-server` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `groovy` | npm-groovy-lint | npm-groovy-lint | — | opt-in |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `gradle build` |
| `:LvimLang run` | `groovy <file>` |
| `:LvimLang test` | `gradle test` |


## Notes

Groovy runs on the JVM; there is no clean mason DAP, so no debugger is offered.