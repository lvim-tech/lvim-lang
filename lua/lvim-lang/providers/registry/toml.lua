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
            formatters = {
                ["taplo"] = { mason = "taplo", efm = { formatCommand = "taplo format -", formatStdin = true } },
            },
            linters = {
                ["taplo"] = {
                    mason = "taplo",
                    efm = {
                        lintCommand = "taplo lint -",
                        lintStdin = true,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%E%trror: %m", "%W%tarning: %m", "%Z%*[ ]┌─ %f:%l:%c" },
                    },
                },
            },
            defaults = { formatter = false, linter = false },
        },
    },
    icons = { statusline = "" },
}
