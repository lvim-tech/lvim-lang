-- lvim-lang.providers.registry.nushell: the Nushell provider (declarative Tier 2).
-- Nushell ships its OWN language server (`nu --lsp`) — no mason; `nu` is resolved through the toolchain.
-- `nu` runs a script. Nushell has no external formatter/linter/debugger.
--
---@module "lvim-lang.providers.registry.nushell"

---@type LvimLangSpecData
return {
    name = "nushell",
    filetypes = { "nu" },
    root_patterns = { ".git" },
    runtime = {
        bin = "nu",
        key = "nu",
        require = true,
        label = "Nushell",
        hint = "Install Nushell (https://www.nushell.sh) and put `nu` on PATH.",
    },
    lsp = { servers = { nushell = { filetypes = { "nu" }, cmd = { "nu", "--lsp" } } }, default = "nushell" },
    ft = { nu = { defaults = {} } },
    commands = {
        run = { cmd = { "nu", "${file}" }, tool = "nu", group = "Run", desc = "nu <file>" },
    },
    icons = { statusline = "󰅩" }, -- Nu
}
