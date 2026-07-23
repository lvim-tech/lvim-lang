-- lvim-lang.providers.registry.html: the HTML provider (declarative Tier 3). vscode-html-language-server is the LSP; prettier / biome / rustywind format; djlint / htmlhint / markuplint lint.
--
---@module "lvim-lang.providers.registry.html"

---@type LvimLangSpecData
return {
    name = "html",
    filetypes = { "html" },
    root_patterns = { "package.json", ".git" },
    lsp = {
        servers = {
            ["html-lsp"] = {
                mason = "html-lsp",
                bin = "vscode-html-language-server",
                cmd = { "vscode-html-language-server", "--stdio" },
                filetypes = { "html" },
            },
        },
        default = "html-lsp",
    },
    ft = {
        html = {
            formatters = {
                ["prettier"] = { mason = "prettier" },
                ["prettierd"] = { mason = "prettierd" },
                ["biome"] = { mason = "biome" },
                ["rustywind"] = { mason = "rustywind" },
            },
            linters = {
                ["djlint"] = { mason = "djlint" },
                ["htmlhint"] = { mason = "htmlhint" },
                ["markuplint"] = { mason = "markuplint" },
            },
            defaults = { formatter = false, linter = false },
        },
    },
    icons = { statusline = "" },
}
