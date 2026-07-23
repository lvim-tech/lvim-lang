-- lvim-lang.providers.registry.fish: the Fish provider (declarative Tier 2).
-- fish-lsp is the LSP; `fish_indent` formats natively. `fish` runs a script. No linter/debugger.
--
---@module "lvim-lang.providers.registry.fish"

---@type LvimLangSpecData
return {
    name = "fish",
    filetypes = { "fish" },
    root_patterns = { ".git" },
    runtime = {
        bin = "fish",
        key = "fish",
        require = false,
        label = "fish shell",
        hint = "Install the fish shell (https://fishshell.com) to run scripts; fish-lsp runs on Node.js.",
    },
    lsp = {
        servers = { ["fish-lsp"] = { mason = "fish-lsp", filetypes = { "fish" }, cmd = { "fish-lsp", "start" } } },
        default = "fish-lsp",
    },
    ft = {
        fish = {
            formatters = { fish_indent = { efm = { formatCommand = "fish_indent", formatStdin = true } } },
            linters = {},
            defaults = { formatter = "fish_indent", linter = false },
        },
    },
    commands = {
        run = { cmd = { "fish", "${file}" }, tool = "fish", group = "Run", desc = "fish <file>" },
    },
    icons = { statusline = "" }, -- fish
}
