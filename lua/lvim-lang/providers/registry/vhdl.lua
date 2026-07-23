-- lvim-lang.providers.registry.vhdl: the VHDL provider (declarative Tier 3 HDL). rust_hdl's vhdl_ls is the LSP.
--
---@module "lvim-lang.providers.registry.vhdl"

---@type LvimLangSpecData
return {
    name = "vhdl",
    filetypes = { "vhdl" },
    root_patterns = { "vhdl_ls.toml", ".git" },
    lsp = {
        servers = { ["rust_hdl"] = { mason = "rust_hdl", bin = "vhdl_ls", filetypes = { "vhdl" } } },
        default = "rust_hdl",
    },
    ft = {
        ["vhdl"] = { defaults = {} },
    },
    icons = { statusline = "" },
}
