# Dockerfile

A declarative Tier 3 provider (infra / DevOps) — data record in `lvim-lang.providers.registry.dockerfile`. dockerfile-language-server is the LSP; hadolint lints.

## LSP

`dockerfile-language-server` (mason) — `docker-langserver --stdio`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `dockerfile` | — | hadolint | opt-in |

All tools are Mason packages and OFF by default — pick one through `setup({ providers = { dockerfile = { ft = { … } } } })`.

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `docker build .` |

## Validation

`lvim-build` offers a file-level **validate** action (`hadolint`), shown only when the checker is installed.
