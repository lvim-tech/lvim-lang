-- lvim-lang.providers.registry.roc: the Roc provider (declarative Tier 2).
-- roc_language_server is the LSP; `roc format` formats natively. `roc build` / `roc dev` (run) /
-- `roc test`. Roc is experimental; debugging support is nascent, so no debugger is offered yet.
--
---@module "lvim-lang.providers.registry.roc"

---@type LvimLangSpecData
return {
    name = "roc",
    filetypes = { "roc" },
    root_patterns = { ".git" },
    runtime = {
        bin = "roc",
        key = "roc",
        require = true,
        label = "Roc",
        hint = "Install Roc (https://www.roc-lang.org) and put `roc` on PATH.",
    },
    lsp = {
        servers = { roc_language_server = { mason = "roc_language_server", filetypes = { "roc" } } },
        default = "roc_language_server",
    },
    ft = {
        roc = {
            formatters = { ["roc-format"] = { efm = { formatCommand = "roc format --stdin", formatStdin = true } } },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        build = { cmd = { "roc", "build", "${file}" }, tool = "roc", group = "Build", desc = "roc build <file>" },
        run = { cmd = { "roc", "dev", "${file}" }, tool = "roc", group = "Run", desc = "roc dev <file>" },
        test = { cmd = { "roc", "test", "${file}" }, tool = "roc", group = "Test", desc = "roc test <file>" },
    },
    icons = { statusline = "󰅩" }, -- Roc
}
