-- lvim-lang.providers.registry.grain: the Grain provider (declarative Tier 2).
-- Grain ships its own language server (`grain lsp`) — no mason; `grain` is resolved through the
-- toolchain. `grain format` formats; `grain compile` / `grain run`. Grain targets WebAssembly.
--
---@module "lvim-lang.providers.registry.grain"

---@type LvimLangSpecData
return {
    name = "grain",
    filetypes = { "grain" },
    root_patterns = { ".git" },
    runtime = {
        bin = "grain",
        key = "grain",
        require = true,
        label = "Grain",
        hint = "Install Grain (https://grain-lang.org) and put `grain` on PATH.",
    },
    lsp = { servers = { grain = { filetypes = { "grain" }, cmd = { "grain", "lsp" } } }, default = "grain" },
    ft = {
        grain = {
            formatters = {
                ["grain-format"] = { efm = { formatCommand = "grain format ${INPUT}", formatStdin = false } },
            },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        build = {
            cmd = { "grain", "compile", "${file}" },
            tool = "grain",
            group = "Build",
            desc = "grain compile <file>",
        },
        run = { cmd = { "grain", "run", "${file}" }, tool = "grain", group = "Run", desc = "grain run <file>" },
    },
    icons = { statusline = "󰅩" }, -- Grain
}
