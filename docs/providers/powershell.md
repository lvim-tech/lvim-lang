# PowerShell

A declarative Tier 3 provider (scientific / legacy) — data record in `lvim-lang.providers.registry.powershell`. PowerShell Editor Services (PSES) is the LSP — launched by a bespoke server module (a pwsh invocation of Start-EditorServices.ps1). PSES provides formatting + PSScriptAnalyzer diagnostics over the LSP. Pester is the test framework.

## LSP

`powershell-editor-services` (mason) — launched via `pwsh` + the bundled Start-EditorServices.ps1 (bespoke `servers/powershell-editor-services.lua`). Requires `pwsh` on PATH.

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `ps1` | (PSES) | (PSES / PSScriptAnalyzer) | — | — |

## Commands

| Command | Description |
| --- | --- |
| (run via lvim-build) | `pwsh -File <file>` |

## Testing

`lvim-test` runs **Pester** — `Invoke-Pester` over `*.Tests.ps1` files (suite-granular).

## Debugging

PSES also provides a debug adapter, but its DAP session wiring is non-trivial and not yet enabled — deferred (not fabricated).
