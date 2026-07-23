# Lean 4

A declarative Tier 3 provider (proof assistant) — data record in `lvim-lang.providers.registry.lean`. The LSP is `lake serve` (from PATH — install the Lean toolchain via elan; no mason for Lean 4). `lake build` compiles.

## LSP

`lake serve` (from PATH; no mason — Lean 4 via elan/lake).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `lean` | — | — | — | — |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `lake build` |

## Validation

`lvim-build` offers `lake build` / `lake test` (project). Proof checking IS the build; no separate DAP.
