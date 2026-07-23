-- lvim-lang.providers.registry.matlab: the MATLAB / Octave provider (declarative Tier 3 scientific).
-- No Mason LSP; MathWorks' matlab-language-server (from PATH, needs a MATLAB install) serves both
-- MATLAB and Octave `.m` files. `octave`/`matlab` run a script.
--
---@module "lvim-lang.providers.registry.matlab"

---@type LvimLangSpecData
return {
    name = "matlab",
    filetypes = { "matlab", "octave" },
    root_patterns = { ".git" },
    lsp = {
        servers = {
            ["matlab-language-server"] = {
                bin = "matlab-language-server",
                cmd = { "matlab-language-server", "--stdio" },
                filetypes = { "matlab", "octave" },
            },
        },
        default = "matlab-language-server",
    },
    ft = { ["matlab"] = { defaults = {} }, ["octave"] = { defaults = {} } },
    commands = {
        run = { cmd = { "octave", "--no-gui", "${file}" }, tool = "octave", group = "Run", desc = "octave <file>" },
    },
    icons = { statusline = "" },
}
