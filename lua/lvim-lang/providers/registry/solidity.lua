-- lvim-lang.providers.registry.solidity: the Solidity provider (declarative Tier 3). The
-- nomicfoundation-solidity-language-server (Hardhat's) is the LSP; `forge fmt` / prettier format;
-- solhint lints. Foundry (`forge`) builds and tests; EVM debugging is via forge/hardhat, not DAP.
--
---@module "lvim-lang.providers.registry.solidity"

---@type LvimLangSpecData
return {
    name = "solidity",
    filetypes = { "solidity" },
    root_patterns = { "foundry.toml", "hardhat.config.js", "hardhat.config.ts", ".git" },
    lsp = {
        servers = {
            ["nomicfoundation-solidity-language-server"] = {
                mason = "nomicfoundation-solidity-language-server",
                cmd = { "nomicfoundation-solidity-language-server", "--stdio" },
                filetypes = { "solidity" },
            },
        },
        default = "nomicfoundation-solidity-language-server",
    },
    ft = {
        ["solidity"] = {
            formatters = {
                ["forge-fmt"] = { efm = { formatCommand = "forge fmt --raw -", formatStdin = true } },
                ["prettier"] = { mason = "prettier" },
            },
            linters = { ["solhint"] = { mason = "solhint" } },
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        build = { cmd = { "forge", "build" }, tool = "forge", group = "Build", desc = "forge build" },
        test = { cmd = { "forge", "test" }, tool = "forge", group = "Test", desc = "forge test" },
    },
    icons = { statusline = "󰡬" },
}
