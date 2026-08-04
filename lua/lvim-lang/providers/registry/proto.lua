-- lvim-lang.providers.registry.proto: the Protocol Buffers provider (declarative Tier 3 data). protols is the LSP; buf formats and lints.
--
---@module "lvim-lang.providers.registry.proto"

---@type LvimLangSpecData
return {
    name = "proto",
    filetypes = { "proto" },
    root_patterns = { "buf.yaml", "buf.work.yaml", ".git" },
    lsp = {
        servers = { protols = { mason = "protols", cmd = { "protols" }, filetypes = { "proto" } } },
        default = "protols",
    },
    ft = {
        ["proto"] = {
            formatters = { ["buf"] = { mason = "buf", efm = { formatCommand = "buf format -", formatStdin = true } } },
            linters = {
                ["buf"] = {
                    mason = "buf",
                    efm = {
                        lintCommand = "buf lint ${INPUT}",
                        lintStdin = false,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%f:%l:%c:%m" },
                        rootMarkers = { "buf.yaml", "buf.yml" },
                    },
                },
            },
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        build = { cmd = { "buf", "build" }, tool = "buf", group = "Build", desc = "buf build" },
        generate = { cmd = { "buf", "generate" }, tool = "buf", group = "Build", desc = "buf generate" },
        lint = { cmd = { "buf", "lint" }, tool = "buf", group = "Lint", desc = "buf lint" },
    },
    icons = { statusline = "󰅩" },
}
