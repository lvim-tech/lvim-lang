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
                ["rustywind"] = {
                    mason = "rustywind",
                    efm = { formatCommand = "rustywind --stdin", formatStdin = true },
                },
            },
            linters = {
                ["djlint"] = {
                    mason = "djlint",
                    efm = {
                        lintCommand = "djlint --lint -",
                        lintStdin = true,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%t%n %l:%c %m" },
                    },
                },
                ["htmlhint"] = {
                    mason = "htmlhint",
                    efm = {
                        lintCommand = "htmlhint --nocolor --format=unix stdin",
                        lintStdin = true,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%f:%l:%c: %m" },
                    },
                },
                -- The default reporter puts everything on one line per finding
                -- ("<markuplint> error: msg (rule) /path:l:c") with real severities; the Simple
                -- reporter pads columns and drops severity. Probe-verified against markuplint 4.x
                -- output through efm 0.0.57 (context/caret lines fall through unmatched).
                ["markuplint"] = {
                    mason = "markuplint",
                    efm = {
                        lintCommand = "markuplint --no-color ${INPUT}",
                        lintStdin = false,
                        lintIgnoreExitCode = true,
                        lintFormats = { "<markuplint> %trror: %m %f:%l:%c", "<markuplint> %tarning: %m %f:%l:%c" },
                    },
                },
            },
            defaults = { formatter = false, linter = false },
        },
    },
    icons = { statusline = "" },
}
