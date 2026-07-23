-- lvim-lang.providers.registry.systemverilog: the SystemVerilog / Verilog provider (declarative Tier 3 HDL). Verible's verible-verilog-ls is the LSP; verible-verilog-format formats; verible-verilog-lint lints.
--
---@module "lvim-lang.providers.registry.systemverilog"

---@type LvimLangSpecData
return {
    name = "systemverilog",
    filetypes = { "verilog", "systemverilog" },
    root_patterns = { ".git" },
    lsp = {
        servers = {
            ["verible-verilog-ls"] = {
                mason = "verible",
                bin = "verible-verilog-ls",
                filetypes = { "verilog", "systemverilog" },
            },
        },
        default = "verible-verilog-ls",
    },
    ft = {
        ["verilog"] = {
            formatters = { ["verible"] = { mason = "verible", bin = "verible-verilog-format" } },
            linters = { ["verible-verilog-lint"] = { mason = "verible", bin = "verible-verilog-lint" } },
            defaults = { formatter = false, linter = false },
        },
        ["systemverilog"] = {
            formatters = { ["verible"] = { mason = "verible", bin = "verible-verilog-format" } },
            linters = { ["verible-verilog-lint"] = { mason = "verible", bin = "verible-verilog-lint" } },
            defaults = { formatter = false, linter = false },
        },
    },
    icons = { statusline = "" },
}
