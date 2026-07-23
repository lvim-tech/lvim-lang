-- lvim-lang.providers.registry.jsonnet: the Jsonnet provider (declarative Tier 3 config/DSL). jsonnet-language-server is the LSP; jsonnetfmt formats.
--
---@module "lvim-lang.providers.registry.jsonnet"

---@type LvimLangSpecData
return {
    name = "jsonnet",
    filetypes = { "jsonnet", "libsonnet" },
    root_patterns = { ".git" },
    lsp = {
        servers = {
            ["jsonnet-language-server"] = { mason = "jsonnet-language-server", filetypes = { "jsonnet", "libsonnet" } },
        },
        default = "jsonnet-language-server",
    },
    ft = {
        ["jsonnet"] = {
            formatters = { ["jsonnetfmt"] = { mason = "jsonnetfmt" } },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
        ["libsonnet"] = {
            formatters = { ["jsonnetfmt"] = { mason = "jsonnetfmt" } },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        run = { cmd = { "jsonnet", "${file}" }, tool = "jsonnet", group = "Run", desc = "jsonnet <file>" },
    },
    icons = { statusline = "" },
}
