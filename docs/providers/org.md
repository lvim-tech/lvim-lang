# Org

A declarative **formatter-only** provider — data record in `lvim-lang.providers.registry.org`. Org has
no LSP server in the mason registry and no prose formatter either; the catalog is `cbfmt`, which
formats the **code inside `#+begin_src` blocks** with the tool(s) named for each language in the
`.cbfmt.toml` found upward from the file. There is no global fallback — without a config the file is
left as it is.

## LSP

None. Registration still flows through lvim-ls: the provider registers an `lsp = {}` entry under its
own name, so the installer offers `cbfmt` on the first `.org` buffer and efm carries the format chain
without ever starting a language-server client.

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `org` | cbfmt | — | `formatter = "cbfmt"` |

Overridable per filetype through `setup({ providers = { org = { ft = { org = { formatter = … } } } } })`
(a single key, a list chain, or `false`).

## Validation

No compile / test / validate step — org is a plain-text format; only the fenced source blocks are
touched, by their own languages' formatters.
