-- lvim-lang.providers.registry.cobol: the COBOL provider (declarative Tier 3 legacy). No Mason LSP;
-- SuperBOL (`superbol-free lsp`, from PATH) is the GnuCOBOL language server. `cobc` compiles.
--
---@module "lvim-lang.providers.registry.cobol"

---@type LvimLangSpecData
return {
    name = "cobol",
    filetypes = { "cobol" },
    root_patterns = { ".git" },
    runtime = {
        bin = "cobc",
        key = "cobc",
        require = true,
        label = "GnuCOBOL (cobc)",
        hint = "Install GnuCOBOL (`cobc`); LSP: SuperBOL (`superbol-free`) from PATH.",
    },
    lsp = {
        servers = {
            ["superbol"] = { bin = "superbol-free", cmd = { "superbol-free", "lsp" }, filetypes = { "cobol" } },
        },
        default = "superbol",
    },
    ft = { ["cobol"] = { defaults = {} } },
    commands = {
        build = { cmd = { "cobc", "-x", "${file}" }, tool = "cobc", group = "Build", desc = "cobc -x <file>" },
    },
    icons = { statusline = "󰅩" },
}
