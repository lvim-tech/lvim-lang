-- lvim-lang.providers.registry.rescript: the ReScript provider (declarative Tier 2).
-- rescript-language-server is the LSP; `rescript format` formats natively. `rescript build` compiles.
-- ReScript targets JavaScript, so no native debugger.
--
---@module "lvim-lang.providers.registry.rescript"

---@type LvimLangSpecData
return {
    name = "rescript",
    filetypes = { "rescript" },
    root_patterns = { "rescript.json", "bsconfig.json", ".git" },
    runtime = {
        bin = "rescript",
        key = "rescript",
        require = true,
        label = "ReScript",
        hint = "Install ReScript (npm i rescript) and put `rescript` on PATH.",
    },
    lsp = {
        servers = { ["rescript-language-server"] = { mason = "rescript-language-server", filetypes = { "rescript" } } },
        default = "rescript-language-server",
    },
    ft = {
        rescript = {
            formatters = {
                ["rescript-format"] = { efm = { formatCommand = "rescript format -stdin .res", formatStdin = true } },
            },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        build = { cmd = { "rescript", "build" }, tool = "rescript", group = "Build", desc = "rescript build" },
        run = {
            cmd = { "rescript", "build", "-w" },
            tool = "rescript",
            group = "Run",
            desc = "rescript build -w (watch)",
        },
    },
    icons = { statusline = "" }, -- ReScript
}
