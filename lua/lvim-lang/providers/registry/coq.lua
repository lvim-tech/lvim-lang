-- lvim-lang.providers.registry.coq: the Coq / Rocq provider (declarative Tier 3). coq-lsp is the LSP.
--
---@module "lvim-lang.providers.registry.coq"

---@type LvimLangSpecData
return {
    name = "coq",
    filetypes = { "coq" },
    root_patterns = { "_CoqProject", ".git" },
    lsp = { servers = { ["coq-lsp"] = { mason = "coq-lsp", filetypes = { "coq" } } }, default = "coq-lsp" },
    ft = {
        ["coq"] = { defaults = {} },
    },
    icons = { statusline = "󰅩" },
}
