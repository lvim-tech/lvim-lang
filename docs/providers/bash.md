# Bash / Shell

A declarative Tier 2 provider. `bash-language-server` is the LSP (it integrates shellcheck for
diagnostics). Filetypes `sh`, `bash`.

## LSP

`bash-language-server` (launched `bash-language-server start`).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `sh` / `bash` | shfmt, beautysh, shellharden | shellcheck, shellharden | bash-debug-adapter | formatter=shfmt, linter=false, debugger=bash-debug-adapter |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang run` | `bash <file>` |
| `:LvimLang check` | `shellcheck <file>` |

## Debugging

`bash-debug-adapter` (bashdb) — launches the current script under the debugger.
