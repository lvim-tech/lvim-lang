-- lvim-lang.providers.registry.json: the JSON / JSONC provider (declarative Tier 3). vscode-json-language-server is the LSP; prettier / biome / fixjson / jq format; jsonlint / biome lint.
--
---@module "lvim-lang.providers.registry.json"

---@type LvimLangSpecData
return {
    name = "json",
    filetypes = { "json", "jsonc", "json5" },
    root_patterns = { "package.json", ".git" },
    lsp = {
        servers = {
            ["json-lsp"] = {
                mason = "json-lsp",
                bin = "vscode-json-language-server",
                cmd = { "vscode-json-language-server", "--stdio" },
                filetypes = { "json", "jsonc" },
                -- The server can format JSON itself, but only when ASKED to at init: without this it
                -- advertises no `textDocument/formatting`, so a JSON buffer has no formatter at all
                -- (the external ones below are opt-in, `formatter = false`) and every save reported
                -- "no matching language servers". Nothing else is needed for plain JSON.
                init_options = { provideFormatter = true },
            },
        },
        default = "json-lsp",
    },
    ft = {
        json = {
            formatters = {
                ["prettier"] = { mason = "prettier" },
                ["prettierd"] = { mason = "prettierd" },
                ["biome"] = { mason = "biome" },
                ["fixjson"] = { mason = "fixjson" },
                ["jq"] = { mason = "jq" },
            },
            linters = { ["jsonlint"] = { mason = "jsonlint" }, ["biome"] = { mason = "biome" } },
            defaults = { formatter = false, linter = false },
        },
        jsonc = {
            formatters = {
                ["prettier"] = { mason = "prettier" },
                ["prettierd"] = { mason = "prettierd" },
                ["biome"] = { mason = "biome" },
            },
            linters = { ["biome"] = { mason = "biome" } },
            defaults = { formatter = false, linter = false },
        },
    },
    icons = { statusline = "" },
}
