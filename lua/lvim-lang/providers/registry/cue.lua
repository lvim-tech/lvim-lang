-- lvim-lang.providers.registry.cue: the CUE provider (declarative Tier 3 config/DSL). cuelsp is the LSP; `cue fmt` formats; `cue vet` validates.
--
---@module "lvim-lang.providers.registry.cue"

---@type LvimLangSpecData
return {
    name = "cue",
    filetypes = { "cue" },
    root_patterns = { ".git" },
    lsp = { servers = { cuelsp = { mason = "cuelsp", filetypes = { "cue" } } }, default = "cuelsp" },
    ft = {
        ["cue"] = {
            formatters = { ["cue-fmt"] = { efm = { formatCommand = "cue fmt -", formatStdin = true } } },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        vet = { cmd = { "cue", "vet" }, tool = "cue", group = "Build", desc = "cue vet" },
        eval = { cmd = { "cue", "eval", "${file}" }, tool = "cue", group = "Run", desc = "cue eval <file>" },
    },
    icons = { statusline = "󰅩" },
}
