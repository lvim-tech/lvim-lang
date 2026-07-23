# Typst

A declarative Tier 3 provider (typesetting) — data record in `lvim-lang.providers.registry.typst`. tinymist is the LSP; typstyle formats. `typst compile` builds a PDF.

## LSP

`tinymist` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `typst` | typstyle | — | — | opt-in |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `typst compile <file>` |
| `:LvimLang watch` | `typst watch <file>` |

## Validation

`lvim-build` offers `typst compile` (build).
