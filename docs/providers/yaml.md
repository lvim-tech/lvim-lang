# YAML

A declarative Tier 3 provider (config / markup / data) — data record in `lvim-lang.providers.registry.yaml`. yaml-language-server is the LSP (schema-aware).

## LSP

`yaml-language-server` (mason) — `yaml-language-server --stdio`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `yaml` | prettier, prettierd, yamlfmt, yamlfix | yamllint, actionlint, spectral | opt-in |

All tools are Mason packages and OFF by default (`formatter = false`, `linter = false`) — pick one per filetype through `setup({ providers = { yaml = { ft = { … } } } })`.

## Validation

No compile / test step (this is a data / markup language). `lvim-build` offers file-level **validate** actions instead — `yamllint` / `prettier --check` — each shown only when its checker is installed.
