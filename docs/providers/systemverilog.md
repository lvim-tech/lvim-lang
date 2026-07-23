# SystemVerilog / Verilog

A declarative Tier 3 provider (HDL) — data record in `lvim-lang.providers.registry.systemverilog`. Verible's verible-verilog-ls is the LSP; verible-verilog-format formats; verible-verilog-lint lints.

## LSP

`verible` (mason, bin `verible-verilog-ls`).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `verilog` / `systemverilog` | verible-verilog-format | verible-verilog-lint | — | opt-in |

## Commands

| Command | Description |
| --- | --- |
| — | — |

## Validation

`lvim-build` offers `verible-verilog-lint`. Simulation debug is simulator-driven, not DAP.
