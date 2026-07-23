-- lvim-lang.providers.registry.yaml: the YAML provider (declarative Tier 3). yaml-language-server is the LSP; prettier / yamlfmt / yamlfix format; yamllint / actionlint / spectral lint.
--
---@module "lvim-lang.providers.registry.yaml"

---@type LvimLangSpecData
return {
    name = "yaml",
    filetypes = { "yaml", "yaml.docker-compose", "yaml.gitlab" },
    root_patterns = { ".git" },
    lsp = {
        servers = {
            ["yaml-language-server"] = {
                mason = "yaml-language-server",
                cmd = { "yaml-language-server", "--stdio" },
                filetypes = { "yaml", "yaml.docker-compose" },
            },
        },
        default = "yaml-language-server",
    },
    ft = {
        yaml = {
            formatters = {
                ["prettier"] = { mason = "prettier" },
                ["prettierd"] = { mason = "prettierd" },
                ["yamlfmt"] = { mason = "yamlfmt" },
                ["yamlfix"] = { mason = "yamlfix" },
            },
            linters = {
                ["yamllint"] = { mason = "yamllint" },
                ["actionlint"] = { mason = "actionlint" },
                ["spectral"] = { mason = "spectral" },
            },
            defaults = { formatter = false, linter = false },
        },
    },
    icons = { statusline = "" },
}
