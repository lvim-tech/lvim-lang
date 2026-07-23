-- lvim-lang.providers.registry.css: the CSS / SCSS / LESS provider (declarative Tier 3). vscode-css-language-server is the LSP; prettier / biome / stylelint format; stylelint / biome lint. (stylelint-lsp also co-attaches as a companion.)
--
---@module "lvim-lang.providers.registry.css"

---@type LvimLangSpecData
return {
    name = "css",
    filetypes = { "css", "scss", "less", "sass" },
    root_patterns = { "package.json", ".git" },
    lsp = {
        servers = {
            ["css-lsp"] = {
                mason = "css-lsp",
                bin = "vscode-css-language-server",
                cmd = { "vscode-css-language-server", "--stdio" },
                filetypes = { "css", "scss", "less" },
            },
        },
        default = "css-lsp",
    },
    ft = {
        css = {
            formatters = {
                ["prettier"] = { mason = "prettier" },
                ["prettierd"] = { mason = "prettierd" },
                ["biome"] = { mason = "biome" },
                ["stylelint"] = { mason = "stylelint" },
            },
            linters = { ["stylelint"] = { mason = "stylelint" }, ["biome"] = { mason = "biome" } },
            defaults = { formatter = false, linter = false },
        },
        scss = {
            formatters = {
                ["prettier"] = { mason = "prettier" },
                ["prettierd"] = { mason = "prettierd" },
                ["stylelint"] = { mason = "stylelint" },
            },
            linters = { ["stylelint"] = { mason = "stylelint" } },
            defaults = { formatter = false, linter = false },
        },
        less = {
            formatters = {
                ["prettier"] = { mason = "prettier" },
                ["prettierd"] = { mason = "prettierd" },
                ["stylelint"] = { mason = "stylelint" },
            },
            linters = { ["stylelint"] = { mason = "stylelint" } },
            defaults = { formatter = false, linter = false },
        },
    },
    icons = { statusline = "" },
}
