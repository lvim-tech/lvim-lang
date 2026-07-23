-- lvim-lang.providers.registry.vim: the Vimscript provider (declarative Tier 3). vim-language-server understands both Vim and Neovim runtime paths.
--
---@module "lvim-lang.providers.registry.vim"

---@type LvimLangSpecData
return {
    name = "vim",
    filetypes = { "vim" },
    root_patterns = { ".git" },
    lsp = {
        servers = {
            ["vim-language-server"] = {
                mason = "vim-language-server",
                cmd = { "vim-language-server", "--stdio" },
                filetypes = { "vim" },
            },
        },
        default = "vim-language-server",
    },
    ft = {
        ["vim"] = { defaults = {} },
    },
    icons = { statusline = "" },
}
