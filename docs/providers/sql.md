# SQL

A declarative Tier 3 provider (infra / DevOps) — data record in `lvim-lang.providers.registry.sql`. sqls is the LSP; sql-formatter / sqlfluff / pg_format format; sqlfluff lints.

## LSP

`sqls` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `sql` | sql-formatter, sqlfluff, pg_format | sqlfluff | opt-in |

All tools are Mason packages and OFF by default — pick one through `setup({ providers = { sql = { ft = { … } } } })`.

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang lint` | `sqlfluff lint <file>` |

## Validation

`lvim-build` offers a file-level **validate** action (`sqlfluff lint`), shown only when the checker is installed.
