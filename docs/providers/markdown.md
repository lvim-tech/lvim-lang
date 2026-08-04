# Markdown

A declarative Tier 3 provider (config / markup / data) — data record in `lvim-lang.providers.registry.markdown`. marksman is the LSP (cross-file links, refactors).

## LSP

`marksman` (mason) — `marksman server`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `markdown` | prettier, prettierd, mdformat, cbfmt, mdslw, remark | markdownlint, markdownlint-cli2, vale, proselint, write-good, alex, textlint | `formatter = { "prettier", "cbfmt" }`, linter opt-in |
| `markdown.mdx`, `mdx` | prettier, prettierd | — | `formatter = "prettier"`, linter opt-in |

All tools are Mason packages. The default formatter is a **chain**: efm runs the tools in order, piping
one's output into the next — `prettier` formats the prose, then `cbfmt` formats the code inside the
fenced blocks. `cbfmt` reads the `.cbfmt.toml` found upward from the file (each repo's own config —
there is no global fallback; without one the fences are left as they are).

A formatter selection may be a single key, a list (a chain), or `false` — per filetype, through
`setup({ providers = { markdown = { ft = { markdown = { formatter = … } } } } })`. Linters stay
opt-in.

## Validation

No compile / test step (this is a data / markup language). `lvim-build` offers file-level **validate** actions instead — `markdownlint` / `prettier --check` — each shown only when its checker is installed.
