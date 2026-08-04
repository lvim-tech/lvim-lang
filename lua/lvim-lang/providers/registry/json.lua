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
                ["prettier"] = {
                    mason = "prettier",
                    efm = { formatCommand = "prettier --stdin-filepath ${INPUT}", formatStdin = true },
                },
                ["prettierd"] = {
                    mason = "prettierd",
                    efm = { formatCommand = "prettierd ${INPUT}", formatStdin = true },
                },
                ["biome"] = {
                    mason = "biome",
                    efm = { formatCommand = "biome format --stdin-file-path=${INPUT}", formatStdin = true },
                },
                ["fixjson"] = { mason = "fixjson", efm = { formatCommand = "fixjson", formatStdin = true } },
                ["jq"] = { mason = "jq", efm = { formatCommand = "jq .", formatStdin = true } },
            },
            linters = {
                ["jsonlint"] = {
                    mason = "jsonlint",
                    efm = {
                        lintCommand = "jsonlint --compact",
                        lintStdin = true,
                        lintIgnoreExitCode = true,
                        lintFormats = { "line %l, col %c, %m", "%f: line %l, col %c, %m" },
                    },
                },
                ["biome"] = {
                    mason = "biome",
                    efm = {
                        lintCommand = "biome lint --reporter=github --stdin-file-path=${INPUT}",
                        lintStdin = true,
                        lintIgnoreExitCode = true,
                        lintFormats = {
                            "::%trror title=%*[^,],file=%f,line=%l,endLine=%*[0-9],col=%c,endColumn=%*[0-9]::%m",
                            "::%tarning title=%*[^,],file=%f,line=%l,endLine=%*[0-9],col=%c,endColumn=%*[0-9]::%m",
                        },
                    },
                },
            },
            defaults = { formatter = false, linter = false },
        },
        jsonc = {
            formatters = {
                ["prettier"] = {
                    mason = "prettier",
                    efm = { formatCommand = "prettier --stdin-filepath ${INPUT}", formatStdin = true },
                },
                ["prettierd"] = {
                    mason = "prettierd",
                    efm = { formatCommand = "prettierd ${INPUT}", formatStdin = true },
                },
                ["biome"] = {
                    mason = "biome",
                    efm = { formatCommand = "biome format --stdin-file-path=${INPUT}", formatStdin = true },
                },
            },
            linters = {
                ["biome"] = {
                    mason = "biome",
                    efm = {
                        lintCommand = "biome lint --reporter=github --stdin-file-path=${INPUT}",
                        lintStdin = true,
                        lintIgnoreExitCode = true,
                        lintFormats = {
                            "::%trror title=%*[^,],file=%f,line=%l,endLine=%*[0-9],col=%c,endColumn=%*[0-9]::%m",
                            "::%tarning title=%*[^,],file=%f,line=%l,endLine=%*[0-9],col=%c,endColumn=%*[0-9]::%m",
                        },
                    },
                },
            },
            defaults = { formatter = false, linter = false },
        },
    },
    icons = { statusline = "" },
}
