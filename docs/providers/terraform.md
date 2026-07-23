# Terraform / HCL

A declarative Tier 3 provider (infra / DevOps) — data record in `lvim-lang.providers.registry.terraform`. terraform-ls is the LSP; `terraform fmt` formats; tflint / tfsec / trivy lint.

## LSP

`terraform-ls` (mason) — `terraform-ls serve`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Defaults |
| --- | --- | --- | --- |
| `terraform` | terraform fmt | tflint, tfsec, trivy | opt-in |
| `hcl` | terraform fmt | — | opt-in |

All tools are Mason packages and OFF by default — pick one through `setup({ providers = { terraform = { ft = { … } } } })`.

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang validate` | `terraform validate` |
| `:LvimLang plan` | `terraform plan` |

## Validation

`lvim-build` offers a file-level **validate** action (`terraform fmt -check` / `tflint`), shown only when the checker is installed.

## Testing

`lvim-test` runs Terraform's native test runner — `terraform test` over `*.tftest.hcl` files (suite-granular; covered files marked by exit code).
