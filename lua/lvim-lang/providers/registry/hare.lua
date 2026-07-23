-- lvim-lang.providers.registry.hare: the Hare provider (declarative Tier 2).
-- hare-lsp (no mason — from PATH) is the LSP. Hare compiles to native binaries, so it debugs with
-- codelldb. `hare build` / `hare run` / `hare test`.
--
---@module "lvim-lang.providers.registry.hare"

---@type LvimLangSpecData
return {
    name = "hare",
    filetypes = { "hare" },
    root_patterns = { ".git" },
    runtime = {
        bin = "hare",
        key = "hare",
        require = true,
        label = "Hare",
        hint = "Install Hare (https://harelang.org/installation/) and put `hare` on PATH.",
    },
    lsp = {
        servers = { ["hare-lsp"] = { filetypes = { "hare" } } }, -- no mason; from PATH
        default = "hare-lsp",
    },
    ft = {
        hare = {
            formatters = {},
            linters = {},
            debuggers = { codelldb = { mason = "codelldb" } },
            defaults = { formatter = false, linter = false, debugger = "codelldb" },
        },
    },
    dap = {
        adapters = { codelldb = { kind = "server" } },
        configurations = {
            hare = {
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
        build = { cmd = { "hare", "build" }, tool = "hare", group = "Build", desc = "hare build" },
        run = { cmd = { "hare", "run", "${file}" }, tool = "hare", group = "Run", desc = "hare run <file>" },
        test = { cmd = { "hare", "test" }, tool = "hare", group = "Test", desc = "hare test" },
    },
    icons = { statusline = "󰅩" }, -- Hare
}
