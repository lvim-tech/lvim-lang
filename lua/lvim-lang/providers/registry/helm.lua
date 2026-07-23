-- lvim-lang.providers.registry.helm: the Helm provider (declarative Tier 3 infra). helm-ls is the LSP; `helm lint` validates a chart.
--
---@module "lvim-lang.providers.registry.helm"

---@type LvimLangSpecData
return {
    name = "helm",
    filetypes = { "helm" },
    root_patterns = { "Chart.yaml", ".git" },
    lsp = {
        servers = {
            ["helm-ls"] = { mason = "helm-ls", bin = "helm_ls", cmd = { "helm_ls", "serve" }, filetypes = { "helm" } },
        },
        default = "helm-ls",
    },
    ft = {
        ["helm"] = {
            formatters = {},
            linters = {},
            defaults = {},
        },
    },
    commands = {
        lint = { cmd = { "helm", "lint", "." }, tool = "helm", group = "Lint", desc = "helm lint ." },
        template = { cmd = { "helm", "template", "." }, tool = "helm", group = "Build", desc = "helm template ." },
    },
    icons = { statusline = "󰌽" },
}
