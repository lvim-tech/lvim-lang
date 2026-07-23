-- lvim-lang.providers.registry.xml: the XML provider (declarative Tier 3). lemminx is the LSP (and formats); xmlformatter / xmllint additionally format.
--
---@module "lvim-lang.providers.registry.xml"

---@type LvimLangSpecData
return {
    name = "xml",
    filetypes = { "xml", "xsd", "xsl", "xslt", "svg" },
    root_patterns = { ".git" },
    lsp = {
        servers = { lemminx = { mason = "lemminx", filetypes = { "xml", "xsd", "xsl", "xslt", "svg" } } },
        default = "lemminx",
    },
    ft = {
        xml = {
            formatters = { ["xmlformatter"] = { mason = "xmlformatter" }, ["xmllint"] = { mason = "xmllint" } },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
    },
    icons = { statusline = "" },
}
