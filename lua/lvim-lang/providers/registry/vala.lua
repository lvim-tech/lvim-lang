-- lvim-lang.providers.registry.vala: the Vala provider (declarative Tier 2).
-- vala-language-server is the LSP; uncrustify formats (mason). Vala compiles (via C) to native binaries,
-- so it debugs with codelldb. meson/ninja build; `valac` compiles a single file.
--
---@module "lvim-lang.providers.registry.vala"

---@type LvimLangSpecData
return {
    name = "vala",
    filetypes = { "vala" },
    root_patterns = { "meson.build", ".git" },
    runtime = {
        bin = "valac",
        key = "valac",
        require = true,
        label = "Vala (valac)",
        hint = "Install the Vala compiler (`valac`) and meson/ninja.",
    },
    lsp = {
        servers = { ["vala-language-server"] = { mason = "vala-language-server", filetypes = { "vala" } } },
        default = "vala-language-server",
    },
    ft = {
        vala = {
            formatters = {
                uncrustify = {
                    mason = "uncrustify",
                    efm = { formatCommand = "uncrustify -l VALA -q", formatStdin = true },
                },
            },
            linters = {},
            debuggers = { codelldb = { mason = "codelldb" } },
            defaults = { formatter = false, linter = false, debugger = "codelldb" },
        },
    },
    dap = {
        adapters = { codelldb = { kind = "server" } },
        configurations = {
            vala = {
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
        build = { cmd = { "ninja", "-C", "build" }, group = "Build", desc = "ninja -C build" },
        run = {
            cmd = { "valac", "${file}", "-o", "/tmp/vala-out" },
            tool = "valac",
            group = "Build",
            desc = "valac <file>",
        },
    },
    icons = { statusline = "" }, -- Vala
}
