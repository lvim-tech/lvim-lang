# Helm

A declarative Tier 3 provider (infra / DevOps) — data record in `lvim-lang.providers.registry.helm`. helm-ls is the LSP; `helm lint` validates a chart.

## LSP

`helm-ls` (mason) — `helm_ls serve`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `helm` | — | — | — |

All tools are Mason packages and OFF by default — pick one through `setup({ providers = { helm = { ft = { … } } } })`.

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang lint` | `helm lint .` |
| `:LvimLang template` | `helm template .` |

## Validation

`lvim-build` offers a file-level **validate** action (`helm lint`), shown only when the checker is installed.
