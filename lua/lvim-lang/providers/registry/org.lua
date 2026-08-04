-- lvim-lang.providers.registry.org: the Org provider (declarative, formatter-only). Org has no LSP
-- server in the mason registry and no prose formatter either — cbfmt is the whole catalog: it formats
-- the CODE inside `#+begin_src` blocks with the tool(s) named in the `.cbfmt.toml` found upward from
-- the file (no config, no formatting — deliberate, there is no global fallback). Registration still
-- flows through lvim-ls: core.lsp registers an `lsp = {}` entry under the provider's own name, so the
-- installer offers cbfmt on the first .org buffer and efm carries the format chain without a client.
--
---@module "lvim-lang.providers.registry.org"

---@type LvimLangSpecData
return {
    name = "org",
    filetypes = { "org" },
    root_patterns = { ".git" },
    ft = {
        org = {
            formatters = {
                ["cbfmt"] = {
                    mason = "cbfmt",
                    efm = { formatCommand = "cbfmt --stdin-filepath ${INPUT} --best-effort", formatStdin = true },
                },
            },
            defaults = { formatter = "cbfmt", linter = false },
        },
    },
    icons = { statusline = "" },
}
