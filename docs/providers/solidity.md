# Solidity

A declarative Tier 3 provider (scientific / legacy) — data record in `lvim-lang.providers.registry.solidity`. The nomicfoundation-solidity-language-server (Hardhat's) is the LSP; `forge fmt` / prettier format; solhint lints. Foundry builds/tests.

## LSP

`nomicfoundation-solidity-language-server` (mason) — `--stdio`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `solidity` | forge fmt, prettier | solhint | — | opt-in |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `forge build` |
| `:LvimLang test` | `forge test` |

## Testing

`lvim-test` runs Foundry — `forge test` over `*.t.sol` files (suite-granular). EVM debugging is via forge/hardhat traces, not DAP.
