-- lvim-lang.providers.registry.powershell: the PowerShell provider (declarative Tier 3). The LSP is
-- PowerShell Editor Services (mason `powershell-editor-services`), whose launch is NOT a static cmd
-- (a pwsh invocation of Start-EditorServices.ps1 with the bundled-modules path) — so it has a bespoke
-- on-disk server module (servers/powershell-editor-services.lua) that the generic shim yields to.
-- PSES also provides the debug adapter; Pester (`Invoke-Pester`) is the test framework.
--
---@module "lvim-lang.providers.registry.powershell"

---@type LvimLangSpecData
return {
    name = "powershell",
    filetypes = { "ps1" },
    root_patterns = { ".git" },
    lsp = {
        servers = { ["powershell-editor-services"] = { mason = "powershell-editor-services", filetypes = { "ps1" } } },
        default = "powershell-editor-services",
    },
    -- PSES itself provides formatting + PSScriptAnalyzer diagnostics over the LSP, so no separate
    -- efm formatter/linter is wired.
    ft = { ["ps1"] = { defaults = {} } },
    icons = { statusline = "󰨊" },
}
