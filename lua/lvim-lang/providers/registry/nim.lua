-- lvim-lang.providers.registry.nim: the Nim provider (declarative Tier 2).
-- nimlangserver is the LSP; nph formats natively (efm, from PATH). Nim compiles to native binaries, so
-- it debugs with codelldb / gdb. `nim c` builds; `nimble test` (unittest) runs the tests.
--
---@module "lvim-lang.providers.registry.nim"

---@type LvimLangSpecData
return {
    name = "nim",
    filetypes = { "nim", "nims", "nimble" },
    root_patterns = { "nim.cfg", "config.nims", ".git" },
    runtime = {
        bin = "nim",
        key = "nim",
        require = true,
        label = "Nim",
        hint = "Install Nim (https://nim-lang.org/install.html) and put `nim` / `nimble` on PATH.",
    },
    lsp = {
        servers = { nimlangserver = { mason = "nimlangserver", filetypes = { "nim" } } },
        default = "nimlangserver",
    },
    ft = {
        nim = {
            formatters = { nph = { efm = { formatCommand = "nph -", formatStdin = true } } },
            linters = {},
            debuggers = { codelldb = { mason = "codelldb" } },
            defaults = { formatter = false, linter = false, debugger = "codelldb" },
        },
    },
    dap = {
        adapters = { codelldb = { kind = "server" } },
        configurations = {
            nim = {
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
        build = { cmd = { "nim", "c", "${file}" }, tool = "nim", group = "Build", desc = "nim c <file>" },
        run = { cmd = { "nim", "c", "-r", "${file}" }, tool = "nim", group = "Run", desc = "nim c -r <file>" },
        test = { cmd = { "nimble", "test" }, tool = "nimble", group = "Test", desc = "nimble test" },
    },
    icons = { statusline = "" }, -- Nim
}
