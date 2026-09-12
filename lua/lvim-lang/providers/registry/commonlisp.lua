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
        -- The system under test is the project's `<name>.asd` at the root, not a hard-coded :app.
        test = {
            cmd = function(ctx)
                local asds = vim.fn.glob(ctx.root .. "/*.asd", true, true)
                if #asds == 0 then
                    vim.notify("lvim-lang: no *.asd system definition at " .. ctx.root, vim.log.levels.WARN, { title = "lvim-lang" })
                    return nil
                end
                table.sort(asds)
                local system = vim.fn.fnamemodify(asds[1], ":t:r")
                return { "sbcl", "--eval", "(asdf:test-system :" .. system .. ")", "--quit" }
            end,
            tool = "sbcl",
            group = "Test",
            desc = "asdf:test-system <root>/*.asd",
        },
    },
    icons = { statusline = "" }, -- Lisp
}
