# LaTeX

A declarative Tier 3 provider (config / DSL) — data record in `lvim-lang.providers.registry.latex`. texlab is the LSP (with latexmk as the build backend); latexindent formats. latexmk builds a PDF.

## LSP

`texlab` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `tex` / `bib` | latexindent | — | opt-in |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `latexmk -pdf <file>` |
| `:LvimLang clean` | `latexmk -c` |

## Validation

`lvim-build` offers a file-level **validate** action (`latexmk -pdf` (build)), shown only when the checker is installed.
