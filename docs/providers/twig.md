# Twig

A declarative Tier 3 provider (web framework) — data record in `lvim-lang.providers.registry.twig`. twiggy (from PATH; no mason) is the LSP; djlint formats and lints Twig templates.

## LSP

`twiggy` (from PATH; no mason — install the twig-language-server / twiggy binary manually).

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `twig` | djlint | djlint | opt-in |

All tools are Mason packages and OFF by default — pick one through `setup({ providers = { twig = { ft = { … } } } })`.

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang lint` | `djlint <file>` |

## Validation

`lvim-build` offers a file-level **validate** action (`djlint`), shown only when the checker is installed.
