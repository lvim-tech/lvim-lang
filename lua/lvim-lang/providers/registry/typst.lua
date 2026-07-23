-- lvim-lang.providers.registry.typst: the Typst provider (declarative Tier 3). tinymist is the LSP; typstyle formats. `typst compile` builds a PDF.
--
---@module "lvim-lang.providers.registry.typst"

---@type LvimLangSpecData
return {
    name = "typst",
    filetypes = { "typst" },
    root_patterns = { ".git" },
    lsp = { servers = { tinymist = { mason = "tinymist", filetypes = { "typst" } } }, default = "tinymist" },
    ft = {
        ["typst"] = {
            formatters = { ["typstyle"] = { mason = "typstyle" } },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        build = {
            cmd = { "typst", "compile", "${file}" },
            tool = "typst",
            group = "Build",
            desc = "typst compile ${file}",
        },
        watch = { cmd = { "typst", "watch", "${file}" }, tool = "typst", group = "Run", desc = "typst watch ${file}" },
    },
    icons = { statusline = "" },
}
