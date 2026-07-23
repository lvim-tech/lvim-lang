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
                ["tflint"] = { mason = "tflint" },
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
