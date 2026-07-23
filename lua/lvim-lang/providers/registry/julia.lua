-- lvim-lang.providers.registry.julia: the Julia provider, as declarative DATA (Tier 2).
-- julia-lsp (LanguageServer.jl, wrapped by mason `julia-lsp`) is the LSP — it formats via JuliaFormatter
-- natively, so no efm tools are wired. `julia` runs the current file; `Pkg.test()` drives the test suite.
-- Julia itself is the user's own runtime (the language server runs on it).
--
---@module "lvim-lang.providers.registry.julia"

---@type LvimLangSpecData
return {
    name = "julia",
    filetypes = { "julia" },
    root_patterns = { "Project.toml", "JuliaProject.toml", ".git" },

    runtime = {
        bin = "julia",
        key = "julia",
        require = true,
        label = "Julia",
        hint = "Install Julia (https://julialang.org/downloads/) and put `julia` on PATH; the language server runs on it.",
    },

    lsp = {
        servers = {
            ["julia-lsp"] = {
                mason = "julia-lsp",
                filetypes = { "julia" },
            },
        },
        default = "julia-lsp",
    },

    -- julia-lsp formats (JuliaFormatter) + lints natively — no efm tools.
    ft = {
        julia = { defaults = {} },
    },

    commands = {
        run = { cmd = { "julia", "${file}" }, tool = "julia", group = "Run", desc = "julia <file>" },
        test = {
            cmd = { "julia", "--project=.", "-e", "using Pkg; Pkg.test()" },
            tool = "julia",
            group = "Test",
            desc = "Pkg.test() — run the project test suite",
        },
    },

    icons = {
        statusline = "", -- the Julia marker (nf-seti-julia)
    },
}
