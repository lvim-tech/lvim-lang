-- lvim-lang.providers.registry.racket: the Racket provider (declarative Tier 2).
-- racket-langserver is a Racket package (no mason) launched through the `racket` binary; `raco fmt`
-- formats. `raco make` builds; `raco test` runs rackunit tests.
--
---@module "lvim-lang.providers.registry.racket"

---@type LvimLangSpecData
return {
    name = "racket",
    filetypes = { "racket", "scheme" },
    root_patterns = { "info.rkt", ".git" },
    runtime = {
        bin = "racket",
        key = "racket",
        require = true,
        label = "Racket",
        hint = "Install Racket (https://racket-lang.org) and the LSP (`raco pkg install racket-langserver`).",
    },
    lsp = {
        servers = {
            ["racket-langserver"] = {
                filetypes = { "racket", "scheme" },
                cmd = { "racket", "-l", "racket-langserver" },
            },
        },
        default = "racket-langserver",
    },
    ft = {
        racket = {
            formatters = { ["raco-fmt"] = { efm = { formatCommand = "raco fmt", formatStdin = true } } },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        build = { cmd = { "raco", "make", "${file}" }, group = "Build", desc = "raco make <file>" },
        run = { cmd = { "racket", "${file}" }, tool = "racket", group = "Run", desc = "racket <file>" },
        test = { cmd = { "raco", "test", "${file}" }, group = "Test", desc = "raco test <file>" },
    },
    icons = { statusline = "" }, -- Racket
}
