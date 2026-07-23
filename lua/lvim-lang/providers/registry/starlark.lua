-- lvim-lang.providers.registry.starlark: the Starlark / Bazel provider (declarative Tier 3 config/DSL). starpls is the LSP; buildifier formats and lints BUILD / .bzl files.
--
---@module "lvim-lang.providers.registry.starlark"

---@type LvimLangSpecData
return {
    name = "starlark",
    filetypes = { "bzl", "starlark" },
    root_patterns = { "WORKSPACE", "WORKSPACE.bazel", "MODULE.bazel", ".git" },
    lsp = {
        servers = {
            ["starpls"] = { mason = "starpls", cmd = { "starpls", "server" }, filetypes = { "bzl", "starlark" } },
        },
        default = "starpls",
    },
    ft = {
        ["bzl"] = {
            formatters = { ["buildifier"] = { mason = "buildifier" } },
            linters = { ["buildifier"] = { mason = "buildifier" } },
            defaults = { formatter = false, linter = false },
        },
        ["starlark"] = {
            formatters = { ["buildifier"] = { mason = "buildifier" } },
            linters = { ["buildifier"] = { mason = "buildifier" } },
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        build = { cmd = { "bazel", "build", "//..." }, tool = "bazel", group = "Build", desc = "bazel build //..." },
        test = { cmd = { "bazel", "test", "//..." }, tool = "bazel", group = "Test", desc = "bazel test //..." },
    },
    icons = { statusline = "" },
}
