# Prolog

A declarative Tier 3 provider (scientific / legacy) — data record in `lvim-lang.providers.registry.prolog`. No Mason LSP; SWI-Prolog's `lsp_server` pack is loaded through swipl. swipl runs a script.

## LSP

`swipl` + the `lsp_server` pack (from PATH; no mason — `swipl -g "pack_install(lsp_server)"`).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `prolog` | — | — | — | — |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang run` | `swipl <file>` |
