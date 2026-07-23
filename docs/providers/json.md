# JSON / JSONC

A declarative Tier 3 provider (config / markup / data) — data record in `lvim-lang.providers.registry.json`. vscode-json-language-server is the LSP.

## LSP

`json-lsp` (mason) — `vscode-json-language-server --stdio`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `json` | prettier, prettierd, biome, fixjson, jq | jsonlint, biome | opt-in |
| `jsonc` | prettier, prettierd, biome | biome | opt-in |

All tools are Mason packages and OFF by default (`formatter = false`, `linter = false`) — pick one per filetype through `setup({ providers = { json = { ft = { … } } } })`.

## Validation

No compile / test step (this is a data / markup language). `lvim-build` offers file-level **validate** actions instead — `jsonlint` / `jq empty` / `prettier --check` — each shown only when its checker is installed.
