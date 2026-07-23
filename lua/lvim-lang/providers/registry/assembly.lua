-- lvim-lang.providers.registry.assembly: the Assembly provider (declarative Tier 3). asm-lsp is
-- the LSP; asmfmt formats (Go-style asm). Assembled/linked binaries are native, so they debug with
-- codelldb.
--
---@module "lvim-lang.providers.registry.assembly"

---@type LvimLangSpecData
return {
    name = "assembly",
    filetypes = { "asm", "nasm" },
    root_patterns = { ".git" },
    lsp = { servers = { ["asm-lsp"] = { mason = "asm-lsp", filetypes = { "asm", "nasm" } } }, default = "asm-lsp" },
    ft = {
        ["asm"] = {
            formatters = { ["asmfmt"] = { mason = "asmfmt" } },
            linters = {},
            debuggers = { codelldb = { mason = "codelldb" } },
            defaults = { formatter = false, linter = false, debugger = "codelldb" },
        },
        ["nasm"] = {
            formatters = { ["asmfmt"] = { mason = "asmfmt" } },
            linters = {},
            debuggers = { codelldb = { mason = "codelldb" } },
            defaults = { formatter = false, linter = false, debugger = "codelldb" },
        },
    },
    dap = {
        adapters = { codelldb = { kind = "server" } },
        configurations = {
            ["asm"] = {
                {
                    adapter = "codelldb",
                    request = "launch",
                    name = "Launch (codelldb)",
                    program = "pick",
                    cwd = "${workspaceFolder}",
                },
            },
            ["nasm"] = {
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
    icons = { statusline = "" },
}
