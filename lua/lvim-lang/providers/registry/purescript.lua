-- lvim-lang.providers.registry.purescript: the PureScript provider (declarative Tier 2).
-- purescript-language-server is the LSP; purescript-tidy (mason, binary `purs-tidy`) is the formatter.
-- `spago build` / `spago test`. PureScript compiles to JavaScript, so no native debugger.
--
---@module "lvim-lang.providers.registry.purescript"

---@type LvimLangSpecData
return {
    name = "purescript",
    filetypes = { "purescript" },
    root_patterns = { "spago.yaml", "spago.dhall", "packages.dhall", ".git" },
    runtime = {
        bin = "purs",
        key = "purs",
        require = true,
        label = "PureScript",
        hint = "Install PureScript + Spago (https://github.com/purescript/spago) and put `purs` / `spago` on PATH.",
    },
    lsp = {
        servers = {
            ["purescript-language-server"] = { mason = "purescript-language-server", filetypes = { "purescript" } },
        },
        default = "purescript-language-server",
    },
    ft = {
        purescript = {
            formatters = {
                ["purescript-tidy"] = {
                    mason = "purescript-tidy",
                    bin = "purs-tidy",
                    efm = { formatCommand = "purs-tidy format", formatStdin = true },
                },
            },
            linters = {},
            defaults = { formatter = "purescript-tidy", linter = false },
        },
    },
    commands = {
        build = { cmd = { "spago", "build" }, tool = "spago", group = "Build", desc = "spago build" },
        test = { cmd = { "spago", "test" }, tool = "spago", group = "Test", desc = "spago test" },
    },
    icons = { statusline = "" }, -- PureScript
}
