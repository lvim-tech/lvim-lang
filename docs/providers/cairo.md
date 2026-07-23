# Cairo

A declarative Tier 3 provider (blockchain) — data record in `lvim-lang.providers.registry.cairo`. cairo-language-server is the LSP. Scarb (`scarb build` / `scarb test`, from PATH) builds and tests.

## LSP

`cairo-language-server` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `cairo` | — | — | — | — |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `scarb build` |
| `:LvimLang test` | `scarb test` |

## Testing

`lvim-test` runs `scarb test` (suite-granular). Scarb resolves from PATH.
