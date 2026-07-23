-- lvim-lang.providers.registry.nginx: the Nginx provider (declarative Tier 3 config/DSL). nginx-language-server provides completion / hover / diagnostics for nginx.conf and vhost files.
--
---@module "lvim-lang.providers.registry.nginx"

---@type LvimLangSpecData
return {
    name = "nginx",
    filetypes = { "nginx" },
    root_patterns = { "nginx.conf", ".git" },
    lsp = {
        servers = { ["nginx-language-server"] = { mason = "nginx-language-server", filetypes = { "nginx" } } },
        default = "nginx-language-server",
    },
    ft = {
        ["nginx"] = { defaults = {} },
    },
    commands = {
        test = { cmd = { "nginx", "-t" }, tool = "nginx", group = "Lint", desc = "nginx -t (config test)" },
    },
    icons = { statusline = "󰪙" },
}
