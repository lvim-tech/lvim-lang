# Assembly

A declarative Tier 3 provider (scientific / legacy) — data record in `lvim-lang.providers.registry.assembly`. asm-lsp is the LSP; asmfmt formats. Assembled/linked binaries are native → codelldb debugging.

## LSP

`asm-lsp` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `asm` / `nasm` | asmfmt | — | codelldb | debugger=codelldb |

## Commands

| Command | Description |
| --- | --- |
| (build via lvim-build) | `nasm -f elf64 <file>` |

## Debugging

Native via **codelldb** (`program = pick`) — assembled binaries are native.
