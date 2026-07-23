# Starlark / Bazel

A declarative Tier 3 provider (config / DSL) — data record in `lvim-lang.providers.registry.starlark`. starpls is the LSP; buildifier formats and lints BUILD / .bzl files.

## LSP

`starpls` (mason) — `starpls server`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `bzl` / `starlark` | buildifier | buildifier | opt-in |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `bazel build //...` |
| `:LvimLang test` | `bazel test //...` |

## Validation

`lvim-build` offers a file-level **validate** action (`buildifier --mode=check`), shown only when the checker is installed.
