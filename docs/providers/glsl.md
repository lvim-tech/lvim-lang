# GLSL

A declarative Tier 3 provider (shaders) — data record in `lvim-lang.providers.registry.glsl`. glsl_analyzer is the LSP; clang-format formats GLSL (C-like) shader sources.

## LSP

`glsl_analyzer` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `glsl` / `vert` / `frag` / `comp` | clang-format | — | — | opt-in |

## Commands

| Command | Description |
| --- | --- |
| — | — |

## Validation

`lvim-build` offers `clang-format --dry-run --Werror` (format check). Shader debugging is GPU-side (RenderDoc), not DAP.
