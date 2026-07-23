# HTML

A declarative Tier 3 provider (config / markup / data) — data record in `lvim-lang.providers.registry.html`. vscode-html-language-server is the LSP. Emmet + Tailwind co-attach as companions.

## LSP

`html-lsp` (mason) — `vscode-html-language-server --stdio`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `html` | prettier, prettierd, biome, rustywind | djlint, htmlhint, markuplint | opt-in |

All tools are Mason packages and OFF by default (`formatter = false`, `linter = false`) — pick one per filetype through `setup({ providers = { html = { ft = { … } } } })`.

## Validation

No compile / test step (this is a data / markup language). `lvim-build` offers file-level **validate** actions instead — `djlint` / `prettier --check` — each shown only when its checker is installed.
