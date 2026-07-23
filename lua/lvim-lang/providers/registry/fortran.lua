-- lvim-lang.providers.registry.fortran: the Fortran provider (declarative Tier 3 scientific).
-- fortls is the LSP; fprettify / findent format. Fortran compiles to a native binary, so it debugs
-- with codelldb. fpm (the Fortran Package Manager) builds / runs / tests.
--
---@module "lvim-lang.providers.registry.fortran"

---@type LvimLangSpecData
return {
    name = "fortran",
    filetypes = { "fortran" },
    root_patterns = { "fpm.toml", ".git" },
    lsp = { servers = { fortls = { mason = "fortls", filetypes = { "fortran" } } }, default = "fortls" },
    ft = {
        ["fortran"] = {
            formatters = { ["fprettify"] = { mason = "fprettify" }, ["findent"] = { mason = "findent" } },
            linters = {},
            debuggers = { codelldb = { mason = "codelldb" } },
            defaults = { formatter = false, linter = false, debugger = "codelldb" },
        },
    },
    dap = {
        adapters = { codelldb = { kind = "server" } },
        configurations = {
            ["fortran"] = {
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
        build = { cmd = { "fpm", "build" }, tool = "fpm", group = "Build", desc = "fpm build" },
        run = { cmd = { "fpm", "run" }, tool = "fpm", group = "Run", desc = "fpm run" },
        test = { cmd = { "fpm", "test" }, tool = "fpm", group = "Test", desc = "fpm test" },
    },
    icons = { statusline = "" },
}
