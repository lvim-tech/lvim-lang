# Grain

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.grain`). Grain ships its own language server (`grain lsp`) — no mason; `grain` is resolved through the toolchain. `grain format` formats; `grain compile` / `grain run`.

## LSP

`grain` — `grain lsp` (from the Grain binary; no mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `grain` | grain-format | — | — | opt-in |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `grain compile <file>` |
| `:LvimLang run` | `grain run <file>` |


## Notes

Grain targets WebAssembly.