-- lvim-lang.providers.registry.prolog: the Prolog provider (declarative Tier 3 legacy). No Mason LSP;
-- SWI-Prolog's `lsp_server` pack is loaded through `swipl` (install: `swipl -g "pack_install(lsp_server)"`).
-- `swipl` runs a script.
--
---@module "lvim-lang.providers.registry.prolog"

---@type LvimLangSpecData
return {
    name = "prolog",
    filetypes = { "prolog" },
    root_patterns = { ".git" },
    runtime = {
        bin = "swipl",
        key = "swipl",
        require = true,
        label = "SWI-Prolog",
        hint = 'Install SWI-Prolog; LSP: swipl -g "pack_install(lsp_server)".',
    },
    lsp = {
        servers = {
            ["swipl-lsp"] = {
                bin = "swipl",
                cmd = {
                    "swipl",
                    "-g",
                    "use_module(library(lsp_server)).",
                    "-g",
                    "lsp_server:main",
                    "-t",
                    "halt",
                    "--",
                    "stdio",
                },
                filetypes = { "prolog" },
            },
        },
        default = "swipl-lsp",
    },
    ft = { ["prolog"] = { defaults = {} } },
    commands = {
        run = { cmd = { "swipl", "${file}" }, tool = "swipl", group = "Run", desc = "swipl <file>" },
    },
    icons = { statusline = "" },
}
