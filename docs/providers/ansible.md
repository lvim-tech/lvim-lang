# Ansible

A declarative Tier 3 provider (infra / DevOps) — data record in `lvim-lang.providers.registry.ansible`. ansible-language-server is the LSP; ansible-lint lints playbooks.

## LSP

`ansible-language-server` (mason) — `ansible-language-server --stdio`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `yaml.ansible` | — | ansible-lint | opt-in |
| `ansible` | — | ansible-lint | opt-in |

All tools are Mason packages and OFF by default — pick one through `setup({ providers = { ansible = { ft = { … } } } })`.

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang lint` | `ansible-lint` |

## Validation

`lvim-build` offers a file-level **validate** action (`ansible-lint`), shown only when the checker is installed.

## Testing

`lvim-test` runs role tests through **molecule** — `molecule test` (converge + verify a scenario under `molecule/`). Suite-granular; requires molecule installed.
