-- lvim-lang.providers.registry.wgsl: the WGSL provider (declarative Tier 3 shaders). wgsl-analyzer is the LSP (WebGPU shading language).
--
---@module "lvim-lang.providers.registry.wgsl"

---@type LvimLangSpecData
return {
    name = "wgsl",
    filetypes = { "wgsl" },
    root_patterns = { ".git" },
    lsp = {
        servers = { ["wgsl-analyzer"] = { mason = "wgsl-analyzer", filetypes = { "wgsl" } } },
        default = "wgsl-analyzer",
    },
    ft = {
        ["wgsl"] = { defaults = {} },
    },
    icons = { statusline = "" },
}
