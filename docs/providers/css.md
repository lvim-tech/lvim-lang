# CSS / SCSS / LESS

A declarative Tier 3 provider (config / markup / data) — data record in `lvim-lang.providers.registry.css`. vscode-css-language-server is the LSP. Stylelint, Emmet and Tailwind co-attach as companions.

## LSP

`css-lsp` (mason) — `vscode-css-language-server --stdio`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `css` | prettier, prettierd, biome, stylelint | stylelint, biome | opt-in |
| `scss` | prettier, prettierd, stylelint | stylelint | opt-in |
| `less` | prettier, prettierd, stylelint | stylelint | opt-in |

All tools are Mason packages and OFF by default (`formatter = false`, `linter = false`) — pick one per filetype through `setup({ providers = { css = { ft = { … } } } })`.

## Validation

No compile / test step (this is a data / markup language). `lvim-build` offers file-level **validate** actions instead — `stylelint` / `prettier --check` — each shown only when its checker is installed.
