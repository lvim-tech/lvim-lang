# Common Lisp

A declarative Tier 2 provider (data record in `lvim-lang.providers.registry.commonlisp`). `cl-lsp` (from PATH) is used when present — otherwise the SLIME/Sly REPL workflow is the norm. `sbcl` is the runtime; ASDF builds/tests a system.

## LSP

`cl-lsp` (from PATH; no mason). Common Lisp's LSP story is immature — SLIME/Sly remain the common editing path.

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `lisp` | — | — | — | — |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang run` | `sbcl --script <file>` |
| `:LvimLang test` | `asdf:test-system` |
