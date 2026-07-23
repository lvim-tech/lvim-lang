# Protocol Buffers

A declarative Tier 3 provider (infra / DevOps) — data record in `lvim-lang.providers.registry.proto`. protols is the LSP; buf formats and lints.

## LSP

`protols` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `proto` | buf | buf | opt-in |

All tools are Mason packages and OFF by default — pick one through `setup({ providers = { proto = { ft = { … } } } })`.

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `buf build` |
| `:LvimLang generate` | `buf generate` |
| `:LvimLang lint` | `buf lint` |

## Validation

`lvim-build` offers a file-level **validate** action (`buf lint`), shown only when the checker is installed.
