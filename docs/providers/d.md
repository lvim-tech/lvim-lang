# D

A declarative Tier 2 provider. `serve-d` is the LSP (it formats via dfmt natively). D compiles to native
binaries, so it debugs with codelldb (default) / lldb-dap — the same native adapters the compiled
providers use. `dub` is the build tool.

## LSP

`serve-d`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `d` | dfmt (efm, dtools) | — | codelldb, lldb-dap | formatter=false, linter=false, debugger=codelldb |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `dub build` |
| `:LvimLang run` | `dub run` |
| `:LvimLang test` | `dub test` |

## Debugging

Native (DWARF) via codelldb / lldb-dap — the launch config prompts for the built executable.
