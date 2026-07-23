# Vala

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.vala`). `vala-language-server` is the LSP; `uncrustify` formats. Vala compiles (via C) to native binaries and debugs with codelldb.

## LSP

`vala-language-server` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `vala` | uncrustify | — | codelldb | debugger=codelldb |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `ninja -C build` |
| `:LvimLang run` | `valac <file>` |


## Debugging

Native via codelldb — Vala compiles to native binaries.