-- lvim-lang.providers.registry.awk: the AWK provider (declarative Tier 3). awk-language-server is the LSP. `awk -f` runs a script.
--
---@module "lvim-lang.providers.registry.awk"

---@type LvimLangSpecData
return {
    name = "awk",
    filetypes = { "awk" },
    root_patterns = { ".git" },
    lsp = {
        servers = { ["awk-language-server"] = { mason = "awk-language-server", filetypes = { "awk" } } },
        default = "awk-language-server",
    },
    ft = {
        ["awk"] = { defaults = {} },
    },
    commands = {
        run = { cmd = { "awk", "-f", "${file}" }, tool = "awk", group = "Run", desc = "awk -f ${file}" },
    },
    icons = { statusline = "" },
}
