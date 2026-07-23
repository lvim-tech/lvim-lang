-- lvim-lang.providers.registry.twig: the Twig provider (declarative Tier 3 web). twiggy (from PATH; no mason) is the LSP; djlint formats and lints Twig templates.
--
---@module "lvim-lang.providers.registry.twig"

---@type LvimLangSpecData
return {
    name = "twig",
    filetypes = { "twig" },
    root_patterns = { "composer.json", ".git" },
    lsp = { servers = { twiggy = { cmd = { "twiggy" }, filetypes = { "twig" } } }, default = "twiggy" },
    ft = {
        ["twig"] = {
            formatters = { ["djlint"] = { mason = "djlint" } },
            linters = { ["djlint"] = { mason = "djlint" } },
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        lint = { cmd = { "djlint", "${file}" }, tool = "djlint", group = "Lint", desc = "djlint <file>" },
    },
    icons = { statusline = "" },
}
