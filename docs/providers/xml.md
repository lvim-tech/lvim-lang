# XML

A declarative Tier 3 provider (config / markup / data) — data record in `lvim-lang.providers.registry.xml`. lemminx is the LSP (and formats).

## LSP

`lemminx` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `xml` | xmlformatter, xmllint | — | opt-in |

All tools are Mason packages and OFF by default (`formatter = false`, `linter = false`) — pick one per filetype through `setup({ providers = { xml = { ft = { … } } } })`.

## Validation

No compile / test step (this is a data / markup language). `lvim-build` offers file-level **validate** actions instead — `xmllint --noout` (well-formedness) — each shown only when its checker is installed.
