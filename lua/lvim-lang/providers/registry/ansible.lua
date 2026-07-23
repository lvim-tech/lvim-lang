-- lvim-lang.providers.registry.ansible: the Ansible provider (declarative Tier 3 infra). ansible-language-server is the LSP; ansible-lint lints playbooks.
--
---@module "lvim-lang.providers.registry.ansible"

---@type LvimLangSpecData
return {
    name = "ansible",
    filetypes = { "yaml.ansible", "ansible" },
    root_patterns = { "ansible.cfg", "site.yml", ".git" },
    lsp = {
        servers = {
            ["ansible-language-server"] = {
                mason = "ansible-language-server",
                cmd = { "ansible-language-server", "--stdio" },
                filetypes = { "yaml.ansible", "ansible" },
            },
        },
        default = "ansible-language-server",
    },
    ft = {
        ["yaml.ansible"] = {
            formatters = {},
            linters = { ["ansible-lint"] = { mason = "ansible-lint" } },
            defaults = { linter = false },
        },
        ["ansible"] = {
            formatters = {},
            linters = { ["ansible-lint"] = { mason = "ansible-lint" } },
            defaults = { linter = false },
        },
    },
    commands = {
        lint = { cmd = { "ansible-lint" }, tool = "ansible-lint", group = "Lint", desc = "ansible-lint" },
    },
    icons = { statusline = "󱂜" },
}
