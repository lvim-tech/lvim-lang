-- lvim-lang.providers.registry.lean: the Lean 4 provider (declarative Tier 3). The LSP is `lake serve` (from PATH — install the Lean toolchain via elan; no mason for Lean 4). `lake build` compiles.
--
---@module "lvim-lang.providers.registry.lean"

---@type LvimLangSpecData
return {
    name = "lean",
    filetypes = { "lean" },
    root_patterns = { "lakefile.lean", "lakefile.toml", "lean-toolchain", ".git" },
    lsp = {
        servers = { leanls = { bin = "lake", cmd = { "lake", "serve" }, filetypes = { "lean" } } },
        default = "leanls",
    },
    ft = {
        ["lean"] = { defaults = {} },
    },
    commands = {
        build = { cmd = { "lake", "build" }, tool = "lake", group = "Build", desc = "lake build" },
    },
    icons = { statusline = "" },
}
