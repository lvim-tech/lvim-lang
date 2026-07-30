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
                -- Without these the server behaves like plain VIM: no Neovim API completions, and no
                -- index of the runtimepath — so completing a plugin's own functions did not work.
                -- Empty `vimruntime` / `runtimepath` mean "ask the running editor", which is why they
                -- are strings, not paths.
                init_options = {
                    isNeovim = true,
                    iskeyword = "@,48-57,_,192-255,-#", -- mirrors Neovim's default word boundaries
                    vimruntime = "",
                    runtimepath = "",
                    diagnostic = { enable = true },
                    indexes = {
                        runtimepath = true,
                        gap = 100, -- ms between indexing bursts (throttle)
                        count = 3, -- files per burst
                        projectRootPatterns = { "runtime", "nvim", "autoload", "plugin" },
                    },
                    suggest = { fromVimruntime = true, fromRuntimepath = true },
                },
            },
        },
        default = "vim-language-server",
    },
    ft = {
        ["vim"] = { defaults = {} },
    },
    icons = { statusline = "" },
}
