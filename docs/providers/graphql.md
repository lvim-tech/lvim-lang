# GraphQL

A declarative Tier 3 provider (config / markup / data) — data record in `lvim-lang.providers.registry.graphql`. graphql-language-service-cli is the LSP.

## LSP

`graphql-language-service-cli` (mason) — `graphql-lsp server --method stream`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `graphql` | prettier, prettierd, biome | — | opt-in |

All tools are Mason packages and OFF by default (`formatter = false`, `linter = false`) — pick one per filetype through `setup({ providers = { graphql = { ft = { … } } } })`.

## Validation

No compile / test step (this is a data / markup language). `lvim-build` offers file-level **validate** actions instead — `prettier --check` — each shown only when its checker is installed.
