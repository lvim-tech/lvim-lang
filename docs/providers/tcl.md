# Tcl

A declarative Tier 3 provider (scientific / legacy) — data record in `lvim-lang.providers.registry.tcl`. The `tclint` Mason package ships all three tools: tclsp (LSP), tclfmt (formatter), tclint (linter). tclsh runs a script; tcltest is the test harness.

## LSP

`tclsp` (from the `tclint` mason package).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `tcl` | tclfmt | tclint | — | opt-in |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang run` | `tclsh <file>` |

## Testing

`lvim-test` runs tcltest — `tclsh <testfile>` over `*.test` files (suite-granular).
