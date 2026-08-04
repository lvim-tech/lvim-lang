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
                -- Same as json-lsp: the server formats CSS itself, but only when asked at init.
                -- Without it a CSS buffer has no formatter at all (the external ones are opt-in).
                init_options = { provideFormatter = true },
            },
        },
        default = "css-lsp",
    },
    ft = {
        css = {
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
                -- stylelint exits 2 when unfixable problems remain, and efm discards formatter
                -- output on non-zero exit — so --fix silently no-ops on a file that still has an
                -- error. Inherent to stylelint-over-efm; pick prettier when that bites.
                ["stylelint"] = {
                    mason = "stylelint",
                    efm = { formatCommand = "stylelint --stdin --stdin-filename ${INPUT} --fix", formatStdin = true },
                },
            },
            linters = {
                ["stylelint"] = {
                    mason = "stylelint",
                    efm = {
                        lintCommand = "stylelint --no-color --formatter unix --stdin --stdin-filename ${INPUT}",
                        lintStdin = true,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%f:%l:%c: %m" },
                        rootMarkers = { ".stylelintrc", ".stylelintrc.json", "stylelint.config.js" },
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
        scss = {
            formatters = {
                ["prettier"] = {
                    mason = "prettier",
                    efm = { formatCommand = "prettier --stdin-filepath ${INPUT}", formatStdin = true },
                },
                ["prettierd"] = {
                    mason = "prettierd",
                    efm = { formatCommand = "prettierd ${INPUT}", formatStdin = true },
                },
                -- stylelint exits 2 when unfixable problems remain, and efm discards formatter
                -- output on non-zero exit — so --fix silently no-ops on a file that still has an
                -- error. Inherent to stylelint-over-efm; pick prettier when that bites.
                ["stylelint"] = {
                    mason = "stylelint",
                    efm = { formatCommand = "stylelint --stdin --stdin-filename ${INPUT} --fix", formatStdin = true },
                },
            },
            linters = {
                ["stylelint"] = {
                    mason = "stylelint",
                    efm = {
                        lintCommand = "stylelint --no-color --formatter unix --stdin --stdin-filename ${INPUT}",
                        lintStdin = true,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%f:%l:%c: %m" },
                        rootMarkers = { ".stylelintrc", ".stylelintrc.json", "stylelint.config.js" },
                    },
                },
            },
            defaults = { formatter = false, linter = false },
        },
        less = {
            formatters = {
                ["prettier"] = {
                    mason = "prettier",
                    efm = { formatCommand = "prettier --stdin-filepath ${INPUT}", formatStdin = true },
                },
                ["prettierd"] = {
                    mason = "prettierd",
                    efm = { formatCommand = "prettierd ${INPUT}", formatStdin = true },
                },
                -- stylelint exits 2 when unfixable problems remain, and efm discards formatter
                -- output on non-zero exit — so --fix silently no-ops on a file that still has an
                -- error. Inherent to stylelint-over-efm; pick prettier when that bites.
                ["stylelint"] = {
                    mason = "stylelint",
                    efm = { formatCommand = "stylelint --stdin --stdin-filename ${INPUT} --fix", formatStdin = true },
                },
            },
            linters = {
                ["stylelint"] = {
                    mason = "stylelint",
                    efm = {
                        lintCommand = "stylelint --no-color --formatter unix --stdin --stdin-filename ${INPUT}",
                        lintStdin = true,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%f:%l:%c: %m" },
                        rootMarkers = { ".stylelintrc", ".stylelintrc.json", "stylelint.config.js" },
                    },
                },
            },
            defaults = { formatter = false, linter = false },
        },
    },
    icons = { statusline = "" },
}
