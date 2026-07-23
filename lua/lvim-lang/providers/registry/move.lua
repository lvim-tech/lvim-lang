-- lvim-lang.providers.registry.move: the Move provider (declarative Tier 3 blockchain). move-analyzer is the LSP. `move build` / `move test` (Aptos / Sui Move CLI).
--
---@module "lvim-lang.providers.registry.move"

---@type LvimLangSpecData
return {
    name = "move",
    filetypes = { "move" },
    root_patterns = { "Move.toml", ".git" },
    lsp = {
        servers = { ["move-analyzer"] = { mason = "move-analyzer", filetypes = { "move" } } },
        default = "move-analyzer",
    },
    ft = {
        ["move"] = { defaults = {} },
    },
    commands = {
        build = { cmd = { "move", "build" }, tool = "move", group = "Build", desc = "move build" },
        test = { cmd = { "move", "test" }, tool = "move", group = "Test", desc = "move test" },
    },
    icons = { statusline = "󰡬" },
}
