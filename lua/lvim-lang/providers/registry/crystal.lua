-- lvim-lang.providers.registry.crystal: the Crystal provider (declarative Tier 2).
-- crystalline is the LSP; `crystal tool format` formats natively (efm). Crystal compiles to native
-- binaries, so it debugs with codelldb. shards is the build tool; `crystal spec` runs the tests.
--
---@module "lvim-lang.providers.registry.crystal"

---@type LvimLangSpecData
return {
    name = "crystal",
    filetypes = { "crystal" },
    root_patterns = { "shard.yml", ".git" },
    runtime = {
        bin = "crystal",
        key = "crystal",
        require = true,
        label = "Crystal",
        hint = "Install Crystal (https://crystal-lang.org/install/) and put `crystal` / `shards` on PATH.",
    },
    lsp = {
        servers = { crystalline = { mason = "crystalline", filetypes = { "crystal" } } },
        default = "crystalline",
    },
    ft = {
        crystal = {
            formatters = {
                ["crystal-format"] = { efm = { formatCommand = "crystal tool format -", formatStdin = true } },
            },
            linters = {},
            debuggers = { codelldb = { mason = "codelldb" }, ["lldb-dap"] = { mason = "lldb-dap" } },
            defaults = { formatter = "crystal-format", linter = false, debugger = "codelldb" },
        },
    },
    dap = {
        adapters = { codelldb = { kind = "server" }, ["lldb-dap"] = { kind = "executable" } },
        configurations = {
            crystal = {
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
        build = { cmd = { "shards", "build" }, tool = "shards", group = "Build", desc = "shards build" },
        run = { cmd = { "crystal", "run", "${file}" }, tool = "crystal", group = "Run", desc = "crystal run <file>" },
        test = { cmd = { "crystal", "spec" }, tool = "crystal", group = "Test", desc = "crystal spec" },
    },
    icons = { statusline = "" }, -- Crystal
}
