-- lvim-lang.providers.registry.tcl: the Tcl provider (declarative Tier 3). The `tclint` Mason
-- package ships all three tools: tclsp (LSP), tclfmt (formatter) and tclint (linter). `tclsh` runs
-- a script; the native `tcltest` package is the test harness.
--
---@module "lvim-lang.providers.registry.tcl"

---@type LvimLangSpecData
return {
    name = "tcl",
    filetypes = { "tcl" },
    root_patterns = { ".git" },
    lsp = { servers = { ["tclsp"] = { mason = "tclint", bin = "tclsp", filetypes = { "tcl" } } }, default = "tclsp" },
    ft = {
        ["tcl"] = {
            formatters = { ["tclfmt"] = { mason = "tclint", bin = "tclfmt" } },
            linters = { ["tclint"] = { mason = "tclint" } },
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        run = { cmd = { "tclsh", "${file}" }, tool = "tclsh", group = "Run", desc = "tclsh <file>" },
    },
    icons = { statusline = "" },
}
