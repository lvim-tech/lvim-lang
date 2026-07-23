-- lvim-lang.providers.registry.elm: the Elm provider (declarative Tier 2).
-- elm-language-server is the LSP; elm-format is the formatter (mason, efm). `elm make` builds; `elm-test`
-- runs the tests. Elm compiles to JavaScript, so no native debugger.
--
---@module "lvim-lang.providers.registry.elm"

---@type LvimLangSpecData
return {
    name = "elm",
    filetypes = { "elm" },
    root_patterns = { "elm.json", ".git" },
    runtime = {
        bin = "elm",
        key = "elm",
        require = true,
        label = "Elm",
        hint = "Install Elm (https://guide.elm-lang.org/install/elm.html) and put `elm` on PATH.",
    },
    lsp = {
        servers = { ["elm-language-server"] = { mason = "elm-language-server", filetypes = { "elm" } } },
        default = "elm-language-server",
    },
    ft = {
        elm = {
            formatters = {
                ["elm-format"] = {
                    mason = "elm-format",
                    efm = { formatCommand = "elm-format --stdin", formatStdin = true },
                },
            },
            linters = {},
            defaults = { formatter = "elm-format", linter = false },
        },
    },
    commands = {
        build = {
            cmd = { "elm", "make", "src/Main.elm" },
            tool = "elm",
            group = "Build",
            desc = "elm make src/Main.elm",
        },
        test = { cmd = { "elm-test" }, ensure = { mason = "elm-test" }, group = "Test", desc = "elm-test" },
    },
    icons = { statusline = "" }, -- Elm
}
