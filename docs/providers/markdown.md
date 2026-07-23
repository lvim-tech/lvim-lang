# Markdown

A declarative Tier 3 provider (config / markup / data) — data record in `lvim-lang.providers.registry.markdown`. marksman is the LSP (cross-file links, refactors).

## LSP

`marksman` (mason) — `marksman server`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `markdown` | prettier, prettierd, mdformat, cbfmt, mdslw, remark | markdownlint, markdownlint-cli2, vale, proselint, write-good, alex, textlint | opt-in |

All tools are Mason packages and OFF by default (`formatter = false`, `linter = false`) — pick one per filetype through `setup({ providers = { markdown = { ft = { … } } } })`.

## Validation

No compile / test step (this is a data / markup language). `lvim-build` offers file-level **validate** actions instead — `markdownlint` / `prettier --check` — each shown only when its checker is installed.
