-- lvim-lang.providers.registry.terraform: the Terraform / HCL provider (declarative Tier 3 infra). terraform-ls is the LSP; `terraform fmt` formats; tflint / tfsec / trivy lint.
--
---@module "lvim-lang.providers.registry.terraform"

---@type LvimLangSpecData
return {
    name = "terraform",
    filetypes = { "terraform", "hcl", "tf" },
    root_patterns = { ".terraform", ".git" },
    lsp = {
        servers = {
            ["terraform-ls"] = {
                mason = "terraform-ls",
                cmd = { "terraform-ls", "serve" },
                filetypes = { "terraform", "hcl" },
            },
        },
        default = "terraform-ls",
    },
    ft = {
        ["terraform"] = {
            formatters = { ["terraform-fmt"] = { efm = { formatCommand = "terraform fmt -", formatStdin = true } } },
            linters = {
                -- tflint lints the ROOT module it runs in (the efm root): files of nested
                -- modules produce no diagnostics from the root run.
                ["tflint"] = {
                    mason = "tflint",
                    efm = {
                        lintCommand = "tflint --no-color --format=compact",
                        lintStdin = false,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%f:%l:%c: %trror - %m", "%f:%l:%c: %tarning - %m", "%f:%l:%c: %totice - %m" },
                        rootMarkers = { ".tflint.hcl" },
                    },
                },
                -- tfsec and trivy are DIRECTORY-level security scanners, not per-line linters: their
                -- output (finding blocks / tables) has no stable line-addressed format for efm to
                -- parse, so they stay install-only here. Running them belongs to a build/validate
                -- action, not the buffer-lint lifecycle.
                ["tfsec"] = { mason = "tfsec" },
                ["trivy"] = { mason = "trivy" },
            },
            defaults = { formatter = false, linter = false },
        },
        ["hcl"] = {
            formatters = { ["terraform-fmt"] = { efm = { formatCommand = "terraform fmt -", formatStdin = true } } },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        validate = {
            cmd = { "terraform", "validate" },
            tool = "terraform",
            group = "Build",
            desc = "terraform validate",
        },
        plan = { cmd = { "terraform", "plan" }, tool = "terraform", group = "Run", desc = "terraform plan" },
    },
    icons = { statusline = "󱁢" },
}
