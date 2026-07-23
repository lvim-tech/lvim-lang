-- lvim-lang.providers.registry.dockerfile: the Dockerfile provider (declarative Tier 3 infra). dockerfile-language-server is the LSP; hadolint lints.
--
---@module "lvim-lang.providers.registry.dockerfile"

---@type LvimLangSpecData
return {
    name = "dockerfile",
    filetypes = { "dockerfile" },
    root_patterns = { ".git" },
    lsp = {
        servers = {
            ["dockerfile-language-server"] = {
                mason = "dockerfile-language-server",
                bin = "docker-langserver",
                cmd = { "docker-langserver", "--stdio" },
                filetypes = { "dockerfile" },
            },
        },
        default = "dockerfile-language-server",
    },
    ft = {
        ["dockerfile"] = {
            formatters = {},
            linters = { ["hadolint"] = { mason = "hadolint" } },
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        build = { cmd = { "docker", "build", "." }, tool = "docker", group = "Build", desc = "docker build ." },
    },
    icons = { statusline = "󰡨" },
}
