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
    ft = (function()
        local block = {
            formatters = {
                ["clang-format"] = {
                    mason = "clang-format",
                    efm = { formatCommand = "clang-format --assume-filename=${INPUT}", formatStdin = true },
                },
            },
            linters = {},
            defaults = { formatter = false, linter = false },
        }
        -- One block for every GLSL stage filetype (glsl / vert / frag / geom / comp / tesc / tese).
        local ft = {}
        for _, name in ipairs({ "glsl", "vert", "frag", "geom", "comp", "tesc", "tese" }) do
            ft[name] = vim.deepcopy(block)
        end
        return ft
    end)(),
    icons = { statusline = "󰛧" },
}
