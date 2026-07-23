# Fish

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.fish`). `fish-lsp` is the LSP; `fish_indent` formats natively (ships with fish). `fish` runs a script.

## LSP

`fish-lsp` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `fish` | fish_indent | — | — | formatter=fish_indent |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang run` | `fish <file>` |
