-- lvim-lang.providers.registry.ada: the Ada provider (declarative Tier 2).
-- ada-language-server is the LSP (it formats via gnatpp). Ada compiles to native binaries, so it debugs
-- with codelldb / gdb. `gprbuild` builds; `gnattest` scaffolds/runs the tests.
--
---@module "lvim-lang.providers.registry.ada"

---@type LvimLangSpecData
return {
    name = "ada",
    filetypes = { "ada" },
    root_patterns = { "alire.toml", ".git" },
    runtime = {
        bin = "gprbuild",
        key = "gprbuild",
        require = true,
        label = "GNAT / Ada toolchain",
        hint = "Install the GNAT toolchain (Alire: https://alire.ada.dev) and put `gprbuild` / `gnat` on PATH.",
    },
    lsp = {
        servers = { ["ada-language-server"] = { mason = "ada-language-server", filetypes = { "ada" } } },
        default = "ada-language-server",
    },
    ft = {
        ada = {
            formatters = {},
            linters = {},
            debuggers = { codelldb = { mason = "codelldb" } },
            -- ada-language-server formats via gnatpp → no efm formatter; codelldb debugs the native binary.
            defaults = { formatter = false, linter = false, debugger = "codelldb" },
        },
    },
    dap = {
        adapters = { codelldb = { kind = "server" } },
        configurations = {
            ada = {
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
        build = { cmd = { "gprbuild" }, tool = "gprbuild", group = "Build", desc = "gprbuild" },
        test = { cmd = { "gnattest" }, group = "Test", desc = "gnattest — scaffold / run the test harness" },
    },
    icons = { statusline = "" }, -- Ada
}
