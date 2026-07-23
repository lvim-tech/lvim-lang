-- lvim-lang.providers.registry.graphql: the GraphQL provider (declarative Tier 3). graphql-language-service-cli is the LSP; prettier / biome format.
--
---@module "lvim-lang.providers.registry.graphql"

---@type LvimLangSpecData
return {
    name = "graphql",
    filetypes = { "graphql", "gql" },
    root_patterns = { "package.json", ".graphqlrc", ".git" },
    lsp = {
        servers = {
            graphql = {
                mason = "graphql-language-service-cli",
                bin = "graphql-lsp",
                cmd = { "graphql-lsp", "server", "--method", "stream" },
                filetypes = { "graphql" },
            },
        },
        default = "graphql",
    },
    ft = {
        graphql = {
            formatters = {
                ["prettier"] = { mason = "prettier" },
                ["prettierd"] = { mason = "prettierd" },
                ["biome"] = { mason = "biome" },
            },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
    },
    icons = { statusline = "" },
}
