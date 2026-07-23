# TOML

A declarative Tier 3 provider (config / markup / data) — data record in `lvim-lang.providers.registry.toml`. taplo is the LSP, formatter and linter.

## LSP

`taplo` (mason) — `taplo lsp stdio`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `toml` | taplo | taplo | opt-in |

All tools are Mason packages and OFF by default (`formatter = false`, `linter = false`) — pick one per filetype through `setup({ providers = { toml = { ft = { … } } } })`.

## Validation

No compile / test step (this is a data / markup language). `lvim-build` offers file-level **validate** actions instead — `taplo check` / `taplo fmt --check` — each shown only when its checker is installed.
