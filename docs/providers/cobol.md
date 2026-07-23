# COBOL

A declarative Tier 3 provider (scientific / legacy) — data record in `lvim-lang.providers.registry.cobol`. No Mason LSP; SuperBOL (`superbol-free lsp`, from PATH) is the GnuCOBOL language server. cobc compiles.

## LSP

`superbol-free lsp` (from PATH; no mason — install SuperBOL / GnuCOBOL manually).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `cobol` | — | — | — | — |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `cobc -x <file>` |
