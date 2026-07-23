-- lvim-lang.providers.registry.markdown: the Markdown provider (declarative Tier 3). marksman is the LSP; prettier / mdformat / cbfmt / mdslw / remark format; markdownlint / vale / proselint / write-good / alex / textlint lint.
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
                ["prettier"] = { mason = "prettier" },
                ["prettierd"] = { mason = "prettierd" },
                ["mdformat"] = { mason = "mdformat" },
                ["cbfmt"] = { mason = "cbfmt" },
                ["mdslw"] = { mason = "mdslw" },
                ["remark"] = { mason = "remark" },
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
            defaults = { formatter = false, linter = false },
        },
    },
    icons = { statusline = "" },
}
