# Move

A declarative Tier 3 provider (blockchain) — data record in `lvim-lang.providers.registry.move`. move-analyzer is the LSP. The Move CLI (`move build` / `move test`, Aptos / Sui) builds and tests.

## LSP

`move-analyzer` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `move` | — | — | — | — |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `move build` |
| `:LvimLang test` | `move test` |

## Testing

`lvim-test` runs `move test` (suite-granular; covered files marked by exit code).
