-- lvim-lang.providers.registry.pascal: the Pascal / Delphi provider (declarative Tier 2).
-- pasls (the Pascal Language Server, from PATH — no mason) is the LSP. Pascal compiles to native
-- binaries, so it debugs with codelldb / gdb. `fpc` compiles a file; `lazbuild` builds a Lazarus project.
--
---@module "lvim-lang.providers.registry.pascal"

---@type LvimLangSpecData
return {
    name = "pascal",
    filetypes = { "pascal" },
    root_patterns = { ".git" },
    runtime = {
        bin = "fpc",
        key = "fpc",
        require = true,
        label = "Free Pascal (fpc)",
        hint = "Install Free Pascal (`fpc`) / Lazarus; the LSP `pasls` from https://github.com/genericptr/pascal-language-server.",
    },
    lsp = { servers = { pasls = { filetypes = { "pascal" } } }, default = "pasls" }, -- from PATH; no mason
    ft = {
        pascal = {
            formatters = {},
            linters = {},
            debuggers = { codelldb = { mason = "codelldb" } },
            defaults = { formatter = false, linter = false, debugger = "codelldb" },
        },
    },
    dap = {
        adapters = { codelldb = { kind = "server" } },
        configurations = {
            pascal = {
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
        build = { cmd = { "fpc", "${file}" }, tool = "fpc", group = "Build", desc = "fpc <file>" },
        run = { cmd = { "fpc", "${file}" }, tool = "fpc", group = "Build", desc = "fpc <file>" },
    },
    icons = { statusline = "󰅩" }, -- Pascal
}
