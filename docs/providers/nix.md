# Nix

A declarative Tier 3 provider (infra / DevOps) — data record in `lvim-lang.providers.registry.nix`. nil is the LSP; nixpkgs-fmt / alejandra / nixfmt format; statix lints.

## LSP

`nil` (mason).

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `nix` | nixpkgs-fmt, alejandra, nixfmt | statix | opt-in |

All tools are Mason packages and OFF by default — pick one through `setup({ providers = { nix = { ft = { … } } } })`.

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `nix build` |

## Validation

`lvim-build` offers a file-level **validate** action (`statix check` / `nixpkgs-fmt --check`), shown only when the checker is installed.
