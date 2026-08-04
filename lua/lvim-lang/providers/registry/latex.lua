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
            -- latexindent's -g /dev/null sinks the indent.log it writes on every run, so stdin
            -- formatting stays side-effect free.
            formatters = {
                ["latexindent"] = {
                    mason = "latexindent",
                    efm = { formatCommand = "latexindent -g /dev/null", formatStdin = true },
                },
            },
            -- Prose / grammar checking for LaTeX goes through the normal LINTER lifecycle — there is
            -- no TeX-specific plumbing for it anywhere else in the ecosystem. Both tools read a .tex
            -- file directly (vale has a LaTeX parser; proselint reads it as prose) and both are
            -- already declared by the markdown provider, so the mason names are the ones lvim-lang
            -- installs elsewhere. `linter = false` keeps the whole thing opt-in: nothing is chosen,
            -- so nothing installs and nothing runs until a user picks one.
            linters = {
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
            },
            defaults = { formatter = false, linter = false },
        },
        ["bib"] = {
            -- latexindent's -g /dev/null sinks the indent.log it writes on every run, so stdin
            -- formatting stays side-effect free.
            formatters = {
                ["latexindent"] = {
                    mason = "latexindent",
                    efm = { formatCommand = "latexindent -g /dev/null", formatStdin = true },
                },
            },
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
