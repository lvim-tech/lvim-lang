-- lvim-lang.providers.registry.toml: the TOML provider (declarative Tier 3). taplo is the LSP, formatter and linter (`taplo lsp` / `taplo fmt` / `taplo check`).
--
---@module "lvim-lang.providers.registry.toml"

---@type LvimLangSpecData
return {
    name = "toml",
    filetypes = { "toml" },
    root_patterns = { ".git" },
    lsp = {
        servers = { taplo = { mason = "taplo", cmd = { "taplo", "lsp", "stdio" }, filetypes = { "toml" } } },
        default = "taplo",
    },
    ft = {
        toml = {
            formatters = { ["taplo"] = { mason = "taplo" } },
            linters = { ["taplo"] = { mason = "taplo" } },
            defaults = { formatter = false, linter = false },
        },
    },
    icons = { statusline = "" },
}
