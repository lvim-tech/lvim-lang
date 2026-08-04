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
                ["markdownlint"] = { mason = "markdownlint" },
                ["markdownlint-cli2"] = { mason = "markdownlint-cli2" },
                ["vale"] = { mason = "vale" },
                ["proselint"] = { mason = "proselint" },
                ["write-good"] = { mason = "write-good" },
                ["alex"] = { mason = "alex" },
                ["textlint"] = { mason = "textlint" },
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
