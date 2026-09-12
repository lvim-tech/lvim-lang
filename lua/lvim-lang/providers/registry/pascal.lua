-- lvim-lang.providers.registry.pascal: the Pascal / Delphi provider (declarative Tier 2).
-- pasls (the Pascal Language Server, from PATH — no mason) is the LSP. Pascal compiles to native
-- binaries, so it debugs with codelldb / gdb. `fpc` compiles a file; `lazbuild` builds a Lazarus project.
--
---@module "lvim-lang.providers.registry.pascal"

---@type LvimLangSpecData
return {
    name = "pascal",
    filetypes = { "pascal" },
    root_patterns = { ".git" },
    runtime = {
        bin = "fpc",
        key = "fpc",
        require = true,
        label = "Free Pascal (fpc)",
        hint = "Install Free Pascal (`fpc`) / Lazarus; the LSP `pasls` from https://github.com/genericptr/pascal-language-server.",
    },
    lsp = { servers = { pasls = { filetypes = { "pascal" } } }, default = "pasls" }, -- from PATH; no mason
    ft = {
        pascal = {
            formatters = {},
            linters = {},
            debuggers = { codelldb = { mason = "codelldb" } },
            defaults = { formatter = false, linter = false, debugger = "codelldb" },
        },
    },
    dap = {
        adapters = { codelldb = { kind = "server" } },
        configurations = {
            pascal = {
                {
                    adapter = "codelldb",
                    request = "launch",
                    name = "Launch (codelldb)",
                    program = "pick",
                    cwd = "${workspaceFolder}",
                },
            },
        },
    },
    commands = {
        build = { cmd = { "fpc", "${file}" }, tool = "fpc", group = "Build", desc = "fpc <file>" },
        -- "run" used to be a second `fpc <file>`: it compiled and never ran anything. Compile, then
        -- execute the binary fpc writes next to the source (the program name, no extension).
        run = {
            cmd = function(ctx)
                if ctx.file == "" then
                    vim.notify("lvim-lang: no file in this buffer to run", vim.log.levels.WARN, { title = "lvim-lang" })
                    return nil
                end
                local exe = vim.fn.fnamemodify(ctx.file, ":r")
                return { "sh", "-c", "fpc " .. vim.fn.shellescape(ctx.file) .. " && " .. vim.fn.shellescape(exe) }
            end,
            tool = "fpc",
            group = "Run",
            desc = "fpc <file> && ./<program>",
        },
    },
    icons = { statusline = "󰅩" }, -- Pascal
}
