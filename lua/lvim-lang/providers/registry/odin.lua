-- lvim-lang.providers.registry.odin: the Odin provider (declarative Tier 2).
-- ols (the Odin Language Server) is the LSP and formats natively. Odin compiles to native binaries, so
-- it debugs with codelldb. `odin build` / `odin run` / `odin test`.
--
---@module "lvim-lang.providers.registry.odin"

---@type LvimLangSpecData
return {
    name = "odin",
    filetypes = { "odin" },
    root_patterns = { "ols.json", ".git" },
    runtime = {
        bin = "odin",
        key = "odin",
        require = true,
        label = "Odin",
        hint = "Install Odin (https://odin-lang.org) and put `odin` on PATH.",
    },
    lsp = {
        servers = { ols = { mason = "ols", filetypes = { "odin" } } },
        default = "ols",
    },
    ft = {
        odin = {
            formatters = {},
            linters = {},
            debuggers = { codelldb = { mason = "codelldb" } },
            -- ols formats natively → no efm formatter; codelldb debugs the native binary.
            defaults = { formatter = false, linter = false, debugger = "codelldb" },
        },
    },
    dap = {
        adapters = { codelldb = { kind = "server" } },
        configurations = {
            odin = {
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
        build = { cmd = { "odin", "build", "." }, tool = "odin", group = "Build", desc = "odin build ." },
        run = { cmd = { "odin", "run", "." }, tool = "odin", group = "Run", desc = "odin run ." },
        test = { cmd = { "odin", "test", "." }, tool = "odin", group = "Test", desc = "odin test ." },
    },
    icons = { statusline = "󰅩" }, -- Odin
}
