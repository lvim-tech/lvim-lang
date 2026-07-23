# Roc

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.roc`). `roc_language_server` is the LSP; `roc format` formats natively. `roc build` / `roc dev` (run) / `roc test`.

## LSP

`roc_language_server` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `roc` | roc-format | — | — | opt-in |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `roc build <file>` |
| `:LvimLang run` | `roc dev <file>` |
| `:LvimLang test` | `roc test <file>` |


## Debugging

Roc compiles to a native binary, so it debugs with **codelldb** (`program = pick`, `cwd = ${workspaceFolder}`) like the other native languages — debug-info quality depends on the still-young Roc toolchain.