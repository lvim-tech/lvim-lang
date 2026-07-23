-- lvim-lang.providers.registry.v: the V provider (declarative Tier 2).
-- v-analyzer is the LSP; `v fmt` formats natively (efm). V compiles to native binaries, so it debugs
-- with codelldb. `v build` / `v run` / `v test`.
--
---@module "lvim-lang.providers.registry.v"

---@type LvimLangSpecData
return {
    name = "v",
    filetypes = { "vlang", "v" },
    root_patterns = { "v.mod", ".git" },
    runtime = {
        bin = "v",
        key = "v",
        require = true,
        label = "V",
        hint = "Install V (https://vlang.io) and put `v` on PATH.",
    },
    lsp = {
        servers = { ["v-analyzer"] = { mason = "v-analyzer", filetypes = { "vlang", "v" } } },
        default = "v-analyzer",
    },
    ft = {
        vlang = {
            formatters = { ["v-fmt"] = { efm = { formatCommand = "v fmt", formatStdin = true } } },
            linters = {},
            debuggers = { codelldb = { mason = "codelldb" } },
            defaults = { formatter = "v-fmt", linter = false, debugger = "codelldb" },
        },
    },
    dap = {
        adapters = { codelldb = { kind = "server" } },
        configurations = {
            vlang = {
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
        build = { cmd = { "v", "." }, tool = "v", group = "Build", desc = "v ." },
        run = { cmd = { "v", "run", "${file}" }, tool = "v", group = "Run", desc = "v run <file>" },
        test = { cmd = { "v", "test", "." }, tool = "v", group = "Test", desc = "v test ." },
    },
    icons = { statusline = "" }, -- V
}
