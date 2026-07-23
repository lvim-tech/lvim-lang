-- lvim-lang.providers.registry.groovy: the Groovy provider (declarative Tier 2).
-- groovy-language-server is the LSP; npm-groovy-lint formats + lints (mason). Gradle builds/tests;
-- `groovy` runs a script. Groovy runs on the JVM (no clean mason DAP), so no debugger is offered.
--
---@module "lvim-lang.providers.registry.groovy"

---@type LvimLangSpecData
return {
    name = "groovy",
    filetypes = { "groovy" },
    root_patterns = { "build.gradle", "settings.gradle", ".git" },
    runtimes = {
        {
            bin = "groovy",
            key = "groovy",
            require = true,
            label = "Groovy",
            hint = "Install Groovy (SDKMAN) and put `groovy` on PATH.",
            sdkman = "groovy",
        },
        { bin = "gradle", key = "gradle", sdkman = "gradle" },
    },
    lsp = {
        servers = { ["groovy-language-server"] = { mason = "groovy-language-server", filetypes = { "groovy" } } },
        default = "groovy-language-server",
    },
    ft = {
        groovy = {
            formatters = {
                ["npm-groovy-lint"] = {
                    mason = "npm-groovy-lint",
                    efm = { formatCommand = "npm-groovy-lint --format --failon none -", formatStdin = true },
                },
            },
            linters = {
                ["npm-groovy-lint"] = {
                    mason = "npm-groovy-lint",
                    efm = {
                        lintCommand = "npm-groovy-lint --failon none ${INPUT}",
                        lintStdin = false,
                        lintFormats = { "%f:%l:%c: %m" },
                    },
                },
            },
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        build = { cmd = { "gradle", "build" }, tool = "gradle", group = "Build", desc = "gradle build" },
        run = { cmd = { "groovy", "${file}" }, tool = "groovy", group = "Run", desc = "groovy <file>" },
        test = { cmd = { "gradle", "test" }, tool = "gradle", group = "Test", desc = "gradle test" },
    },
    icons = { statusline = "" }, -- Groovy
}
