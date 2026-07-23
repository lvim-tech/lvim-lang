-- lvim-lang.providers.registry.cairo: the Cairo provider (declarative Tier 3 blockchain). cairo-language-server is the LSP. Scarb (`scarb build` / `scarb test`, from PATH) is the build/test tool.
--
---@module "lvim-lang.providers.registry.cairo"

---@type LvimLangSpecData
return {
    name = "cairo",
    filetypes = { "cairo" },
    root_patterns = { "Scarb.toml", ".git" },
    lsp = {
        servers = { ["cairo-language-server"] = { mason = "cairo-language-server", filetypes = { "cairo" } } },
        default = "cairo-language-server",
    },
    ft = {
        ["cairo"] = { defaults = {} },
    },
    commands = {
        build = { cmd = { "scarb", "build" }, tool = "scarb", group = "Build", desc = "scarb build" },
        test = { cmd = { "scarb", "test" }, tool = "scarb", group = "Test", desc = "scarb test" },
    },
    icons = { statusline = "" },
}
