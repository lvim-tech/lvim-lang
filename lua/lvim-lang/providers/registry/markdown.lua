-- lvim-lang.providers.registry.markdown: the Markdown provider (declarative Tier 3). marksman is the
-- LSP; prettier / prettierd / mdformat / cbfmt / mdslw / remark format; markdownlint / vale / proselint
-- / write-good / alex / textlint lint. The default formatter is a CHAIN — prettier for the prose, then
-- cbfmt for the code inside the fences (it reads the `.cbfmt.toml` found upward from the file, so each
-- repo's own config drives how its fenced blocks are formatted; no config, no fence formatting).
--
---@module "lvim-lang.providers.registry.markdown"

---@type LvimLangSpecData
return {
    name = "markdown",
    filetypes = { "markdown", "markdown.mdx", "mdx" },
    root_patterns = { ".git", "package.json" },
    lsp = {
        servers = {
            marksman = {
                mason = "marksman",
                cmd = { "marksman", "server" },
                filetypes = { "markdown", "markdown.mdx" },
            },
        },
        default = "marksman",
    },
    ft = {
        markdown = {
            formatters = {
                ["prettier"] = {
                    mason = "prettier",
                    efm = { formatCommand = "prettier --stdin-filepath ${INPUT}", formatStdin = true },
                },
                ["prettierd"] = {
                    mason = "prettierd",
                    efm = { formatCommand = "prettierd ${INPUT}", formatStdin = true },
                },
                ["mdformat"] = {
                    mason = "mdformat",
                    efm = { formatCommand = "mdformat -", formatStdin = true },
                },
                ["cbfmt"] = {
                    mason = "cbfmt",
                    efm = { formatCommand = "cbfmt --stdin-filepath ${INPUT} --best-effort", formatStdin = true },
                },
                ["mdslw"] = {
                    mason = "mdslw",
                    efm = { formatCommand = "mdslw", formatStdin = true },
                },
                ["remark"] = {
                    mason = "remark",
                    efm = { formatCommand = "remark --no-color --silent", formatStdin = true },
                },
            },
            linters = {
                ["markdownlint"] = {
                    mason = "markdownlint",
                    efm = {
                        lintCommand = "markdownlint --stdin",
                        lintStdin = true,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%f:%l:%c %m", "%f:%l %m" },
                    },
                },
                ["markdownlint-cli2"] = {
                    mason = "markdownlint-cli2",
                    efm = {
                        lintCommand = "markdownlint-cli2 ${INPUT}",
                        lintStdin = false,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%f:%l:%c %m", "%f:%l %m" },
                    },
                },
                ["vale"] = {
                    mason = "vale",
                    efm = {
                        lintCommand = "vale --output=line ${INPUT}",
                        lintStdin = false,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%f:%l:%c:%m" },
                        rootMarkers = { ".vale.ini", "_vale.ini" },
                    },
                },
                ["proselint"] = {
                    mason = "proselint",
                    efm = {
                        lintCommand = "proselint ${INPUT}",
                        lintStdin = false,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%f:%l:%c: %m" },
                    },
                },
                ["write-good"] = {
                    mason = "write-good",
                    efm = {
                        lintCommand = "write-good --parse ${INPUT}",
                        lintStdin = false,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%f:%l:%c:%m" },
                    },
                },
                ["alex"] = {
                    mason = "alex",
                    efm = {
                        lintCommand = "alex --quiet --stdin",
                        lintStdin = true,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%*[ ]%l:%c-%*[0-9]:%*[0-9]%*[ ]%tarning%*[ ]%m" },
                    },
                },
                ["textlint"] = {
                    mason = "textlint",
                    efm = {
                        lintCommand = "textlint --no-color --format unix --stdin --stdin-filename ${INPUT}",
                        lintStdin = true,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%f:%l:%c: %m" },
                        rootMarkers = { ".textlintrc", ".textlintrc.json" },
                    },
                },
            },
            defaults = { formatter = { "prettier", "cbfmt" }, linter = false },
        },
        ["markdown.mdx"] = {
            formatters = {
                ["prettier"] = {
                    mason = "prettier",
                    efm = { formatCommand = "prettier --stdin-filepath ${INPUT}", formatStdin = true },
                },
                ["prettierd"] = {
                    mason = "prettierd",
                    efm = { formatCommand = "prettierd ${INPUT}", formatStdin = true },
                },
            },
            defaults = { formatter = "prettier", linter = false },
        },
        mdx = {
            formatters = {
                ["prettier"] = {
                    mason = "prettier",
                    efm = { formatCommand = "prettier --stdin-filepath ${INPUT}", formatStdin = true },
                },
                ["prettierd"] = {
                    mason = "prettierd",
                    efm = { formatCommand = "prettierd ${INPUT}", formatStdin = true },
                },
            },
            defaults = { formatter = "prettier", linter = false },
        },
    },
    icons = { statusline = "" },
}
