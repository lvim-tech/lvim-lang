# Julia

A declarative Tier 2 provider. `julia-lsp` (LanguageServer.jl, wrapped by mason) is the LSP — it formats
via JuliaFormatter natively. mason ships no Julia formatter/linter/debugger beyond the LSP (Julia debugs
via Debugger.jl, not DAP), so the catalog is LSP + run/test.

## LSP

`julia-lsp`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `julia` | — (LSP owns) | — | — | — |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang run` | `julia <file>` |
| `:LvimLang test` | `Pkg.test()` |
