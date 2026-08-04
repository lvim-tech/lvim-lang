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
                ["prettier"] = {
                    mason = "prettier",
                    efm = { formatCommand = "prettier --stdin-filepath ${INPUT}", formatStdin = true },
                },
                ["prettierd"] = {
                    mason = "prettierd",
                    efm = { formatCommand = "prettierd ${INPUT}", formatStdin = true },
                },
                ["yamlfmt"] = { mason = "yamlfmt", efm = { formatCommand = "yamlfmt -in", formatStdin = true } },
                ["yamlfix"] = { mason = "yamlfix", efm = { formatCommand = "yamlfix -", formatStdin = true } },
            },
            linters = {
                ["yamllint"] = {
                    mason = "yamllint",
                    efm = {
                        lintCommand = "yamllint --format parsable -",
                        lintStdin = true,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%f:%l:%c: [%trror] %m", "%f:%l:%c: [%tarning] %m" },
                    },
                },
                ["actionlint"] = {
                    mason = "actionlint",
                    efm = {
                        lintCommand = "actionlint -no-color -oneline -",
                        lintStdin = true,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%f:%l:%c: %m" },
                        rootMarkers = { ".github" },
                    },
                },
                ["spectral"] = {
                    mason = "spectral",
                    efm = {
                        lintCommand = "spectral lint --quiet --format text ${INPUT}",
                        lintStdin = false,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%f:%l:%c %trror %m", "%f:%l:%c %tarning %m" },
                        rootMarkers = { ".spectral.yaml", ".spectral.yml", ".spectral.json" },
                    },
                },
            },
            defaults = { formatter = false, linter = false },
        },
    },
    icons = { statusline = "" },
}
