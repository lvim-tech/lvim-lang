# Astro

A declarative Tier 3 provider (web framework) — data record in `lvim-lang.providers.registry.astro`. astro-language-server is the LSP; prettier / rustywind format; eslint_d lints. Emmet + Tailwind co-attach as companions.

## LSP

`astro-language-server` (mason) — `astro-ls --stdio`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `astro` | prettier, prettierd, rustywind | eslint_d | opt-in |

All tools are Mason packages and OFF by default — pick one through `setup({ providers = { astro = { ft = { … } } } })`.

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang build` | `npm run build` |
| `:LvimLang dev` | `npm run dev` |

## Validation

`lvim-build` offers a file-level **validate** action (`prettier --check` / `eslint_d`), shown only when the checker is installed.

## Debugging

Astro apps run in the browser, so they debug through **js-debug** (`js-debug-adapter`, the `pwa-chrome` launch type) against the running dev server (`http://localhost:4321`, `webRoot = ${workspaceFolder}`); `firefox-debug-adapter` is the Firefox alternative. Start the dev server (`:LvimLang dev`), then launch the config.

## Testing

No dedicated adapter: component tests run through the JavaScript test runner (vitest / jest) over the whole project — the TypeScript/JavaScript tooling — not per-framework.
