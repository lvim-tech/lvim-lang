-- lvim-lang.providers.registry.glsl: the GLSL provider (declarative Tier 3 shaders). glsl_analyzer is the LSP; clang-format formats.
--
---@module "lvim-lang.providers.registry.glsl"

---@type LvimLangSpecData
return {
    name = "glsl",
    filetypes = { "glsl", "vert", "frag", "geom", "comp", "tesc", "tese" },
    root_patterns = { ".git" },
    lsp = {
        servers = {
            ["glsl_analyzer"] = {
                mason = "glsl_analyzer",
                filetypes = { "glsl", "vert", "frag", "geom", "comp", "tesc", "tese" },
            },
        },
        default = "glsl_analyzer",
    },
    ft = {
        ["glsl"] = {
            formatters = { ["clang-format"] = { mason = "clang-format" } },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
        ["vert"] = {
            formatters = { ["clang-format"] = { mason = "clang-format" } },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
        ["frag"] = {
            formatters = { ["clang-format"] = { mason = "clang-format" } },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
        ["comp"] = {
            formatters = { ["clang-format"] = { mason = "clang-format" } },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
    },
    icons = { statusline = "󰛧" },
}
