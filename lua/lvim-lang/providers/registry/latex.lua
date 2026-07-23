-- lvim-lang.providers.registry.latex: the LaTeX provider (declarative Tier 3). texlab is the LSP (with latexmk as the build backend); latexindent formats. `latexmk` builds a PDF.
--
---@module "lvim-lang.providers.registry.latex"

---@type LvimLangSpecData
return {
    name = "latex",
    filetypes = { "tex", "plaintex", "bib" },
    root_patterns = { ".texlabroot", "texlabroot", ".latexmkrc", ".git" },
    lsp = { servers = { texlab = { mason = "texlab", filetypes = { "tex", "plaintex", "bib" } } }, default = "texlab" },
    ft = {
        ["tex"] = {
            formatters = { ["latexindent"] = { mason = "latexindent" } },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
        ["bib"] = {
            formatters = { ["latexindent"] = { mason = "latexindent" } },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        build = {
            cmd = { "latexmk", "-pdf", "${file}" },
            tool = "latexmk",
            group = "Build",
            desc = "latexmk -pdf <file>",
        },
        clean = { cmd = { "latexmk", "-c" }, tool = "latexmk", group = "Build", desc = "latexmk -c" },
    },
    icons = { statusline = "" },
}
