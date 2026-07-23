# Perl

A declarative Tier 2 provider. `perlnavigator` is the LSP (it can drive perltidy / perlcritic itself).
perltidy / perlcritic are offered over efm (CPAN tools, from PATH). Debugging is `perl-debug-adapter`.

## LSP

`perlnavigator` (launched `perlnavigator --stdio`).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `perl` | perltidy (efm, CPAN) | perlcritic (efm, CPAN) | perl-debug-adapter | formatter=false, linter=false, debugger=perl-debug-adapter |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang run` | `perl <file>` |
| `:LvimLang test` | `prove -lr t` |

## Debugging

`perl-debug-adapter` — launches the current file under the debugger.
