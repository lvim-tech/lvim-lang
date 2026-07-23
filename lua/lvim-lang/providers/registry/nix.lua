-- lvim-lang.providers.registry.nix: the Nix provider (declarative Tier 3 infra). nil is the LSP; nixpkgs-fmt / alejandra / nixfmt format; statix lints.
--
---@module "lvim-lang.providers.registry.nix"

---@type LvimLangSpecData
return {
    name = "nix",
    filetypes = { "nix" },
    root_patterns = { "flake.nix", ".git" },
    lsp = { servers = { ["nil"] = { mason = "nil", cmd = { "nil" }, filetypes = { "nix" } } }, default = "nil" },
    ft = {
        ["nix"] = {
            formatters = {
                ["nixpkgs-fmt"] = { mason = "nixpkgs-fmt" },
                ["alejandra"] = { mason = "alejandra" },
                ["nixfmt"] = { mason = "nixfmt" },
            },
            linters = { ["statix"] = { mason = "statix" } },
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        build = { cmd = { "nix", "build" }, tool = "nix", group = "Build", desc = "nix build" },
    },
    icons = { statusline = "󱄅" },
}
