# Jsonnet

A declarative Tier 3 provider (config / DSL) — data record in `lvim-lang.providers.registry.jsonnet`. jsonnet-language-server is the LSP; jsonnetfmt formats.

## LSP

`jsonnet-language-server` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `jsonnet` / `libsonnet` | jsonnetfmt | — | opt-in |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang run` | `jsonnet <file>` |

## Validation

`lvim-build` offers a file-level **validate** action (`jsonnetfmt -test`), shown only when the checker is installed.
