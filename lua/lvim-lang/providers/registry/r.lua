-- lvim-lang.providers.registry.r: the R provider, as declarative DATA (Tier 2).
-- r-languageserver (the `languageserver` R package, wrapped by mason) is the default LSP — it formats
-- (styler) and lints (lintr) natively. The catalog also OFFERS `air` (a fast R formatter/LSP) both as
-- an efm formatter and an ALTERNATIVE server (set lsp.server = "air"). `Rscript` runs the current file;
-- `devtools::test()` drives the testthat suite. mason ships no R debug adapter (R debugs via browser()),
-- so no debugger is offered. R itself is the user's own runtime.
--
---@module "lvim-lang.providers.registry.r"

---@type LvimLangSpecData
return {
    name = "r",
    filetypes = { "r", "rmd" },
    root_patterns = { "DESCRIPTION", ".git" },

    runtime = {
        bin = "R",
        key = "R",
        require = true,
        label = "R",
        hint = "Install R (https://www.r-project.org/) and put `R` / `Rscript` on PATH; the language server runs on it.",
    },

    lsp = {
        servers = {
            ["r-languageserver"] = {
                mason = "r-languageserver",
                filetypes = { "r", "rmd" },
            },
            -- `air` is a fast R formatter that also speaks LSP; opt-in via lsp.server = "air".
            air = {
                mason = "air",
                bin = "air",
                filetypes = { "r" },
                cmd = { "air", "language-server" },
            },
        },
        default = "r-languageserver",
    },

    ft = {
        r = {
            formatters = {
                -- `air format -` formats R from stdin to stdout (much faster than styler).
                air = { mason = "air", efm = { formatCommand = "air format -", formatStdin = true } },
            },
            linters = {},
            -- r-languageserver formats (styler) natively → the efm formatter is opt-in.
            defaults = { formatter = false, linter = false },
        },
        rmd = { defaults = {} },
    },

    commands = {
        run = { cmd = { "Rscript", "${file}" }, group = "Run", desc = "Rscript <file>" },
        test = {
            cmd = { "Rscript", "-e", "devtools::test()" },
            group = "Test",
            desc = "devtools::test() — run the package test suite",
        },
    },

    icons = {
        statusline = "", -- the R marker (nf-seti-r)
    },
}
