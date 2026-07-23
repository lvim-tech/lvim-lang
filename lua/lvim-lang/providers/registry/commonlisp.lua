-- lvim-lang.providers.registry.commonlisp: the Common Lisp provider (declarative Tier 2).
-- Common Lisp has no mason LSP; `cl-lsp` (from PATH) is used when present — otherwise the SLIME/Sly
-- REPL workflow is the norm. `sbcl` is the runtime; ASDF builds/tests a system.
--
---@module "lvim-lang.providers.registry.commonlisp"

---@type LvimLangSpecData
return {
    name = "commonlisp",
    filetypes = { "lisp" },
    root_patterns = { ".git" },
    runtime = {
        bin = "sbcl",
        key = "sbcl",
        require = true,
        label = "Common Lisp (SBCL)",
        hint = "Install SBCL (http://www.sbcl.org) and put `sbcl` on PATH. LSP: install cl-lsp separately.",
    },
    lsp = { servers = { ["cl-lsp"] = { filetypes = { "lisp" } } }, default = "cl-lsp" }, -- from PATH; no mason
    ft = { lisp = { defaults = {} } },
    commands = {
        run = { cmd = { "sbcl", "--script", "${file}" }, tool = "sbcl", group = "Run", desc = "sbcl --script <file>" },
        test = {
            cmd = { "sbcl", "--eval", "(asdf:test-system :app)", "--quit" },
            tool = "sbcl",
            group = "Test",
            desc = "asdf:test-system",
        },
    },
    icons = { statusline = "" }, -- Lisp
}
