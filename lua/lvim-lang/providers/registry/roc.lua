-- lvim-lang.providers.registry.roc: the Roc provider (declarative Tier 2).
-- roc_language_server is the LSP; `roc format` formats natively. `roc build` / `roc dev` (run) /
-- `roc test`. Roc compiles to a native binary, so it debugs with codelldb like the other native
-- languages — debug-info quality depends on the (still-young) Roc toolchain.
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
            debuggers = { codelldb = { mason = "codelldb" } },
            defaults = { formatter = false, linter = false, debugger = "codelldb" },
        },
    },
    dap = {
        adapters = { codelldb = { kind = "server" } },
        configurations = {
            roc = {
                {
                    adapter = "codelldb",
                    request = "launch",
                    name = "Launch (codelldb)",
                    program = "pick",
                    cwd = "${workspaceFolder}",
                },
            },
        },
    },
    commands = {
        build = { cmd = { "roc", "build", "${file}" }, tool = "roc", group = "Build", desc = "roc build <file>" },
        run = { cmd = { "roc", "dev", "${file}" }, tool = "roc", group = "Run", desc = "roc dev <file>" },
        test = { cmd = { "roc", "test", "${file}" }, tool = "roc", group = "Test", desc = "roc test <file>" },
    },
    icons = { statusline = "󰅩" }, -- Roc
}
