# MATLAB / Octave

A declarative Tier 3 provider (scientific / legacy) — data record in `lvim-lang.providers.registry.matlab`. No Mason LSP; MathWorks' matlab-language-server (from PATH, needs a MATLAB install) serves both MATLAB and Octave `.m` files. octave runs a script.

## LSP

`matlab-language-server --stdio` (from PATH; no mason — needs a MATLAB installation).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `matlab` / `octave` | — | — | — | — |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang run` | `octave <file>` |
