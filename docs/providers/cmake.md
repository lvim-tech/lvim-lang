# CMake

A declarative Tier 3 provider (config / DSL) — data record in `lvim-lang.providers.registry.cmake`. cmake-language-server is the LSP; gersemi / cmake-format format; cmake-lint lints. `lvim-build` also detects CMakeLists.txt for configure / build / ctest.

## LSP

`cmake-language-server` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `cmake` | gersemi, cmake-format | cmake-lint | opt-in |

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang configure` | `cmake -B build` |
| `:LvimLang build` | `cmake --build build` |
