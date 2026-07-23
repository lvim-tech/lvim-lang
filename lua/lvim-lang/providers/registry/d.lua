-- lvim-lang.providers.registry.d: the D provider, as declarative DATA (Tier 2).
-- serve-d is the LSP (mason `serve-d`); it formats via dfmt natively. dfmt is OFFERED over efm as an
-- opt-in formatter (it ships with the D toolchain / dtools, not mason — resolved from PATH). D compiles
-- to native binaries with DWARF debug info, so it debugs with codelldb (default) / lldb-dap — the same
-- native adapters the compiled-language providers use. `dub` is the build tool: build / run / test.
--
---@module "lvim-lang.providers.registry.d"

---@type LvimLangSpecData
return {
    name = "d",
    filetypes = { "d" },
    root_patterns = { "dub.json", "dub.sdl", ".git" },

    runtime = {
        bin = "dub",
        key = "dub",
        require = true,
        label = "D toolchain (dub)",
        hint = "Install the D toolchain (dmd / ldc + dub) from https://dlang.org/download.html and put `dub` on "
            .. "PATH; build / run / test go through it. dfmt ships with dtools.",
    },

    lsp = {
        servers = {
            ["serve-d"] = {
                mason = "serve-d",
                filetypes = { "d" },
            },
        },
        default = "serve-d",
    },

    ft = {
        d = {
            formatters = {
                dfmt = { efm = { formatCommand = "dfmt", formatStdin = true } },
            },
            linters = {},
            debuggers = {
                codelldb = { mason = "codelldb" },
                ["lldb-dap"] = { mason = "lldb-dap" },
            },
            -- serve-d formats via dfmt natively → the efm formatter is opt-in; codelldb is default debug.
            defaults = { formatter = false, linter = false, debugger = "codelldb" },
        },
    },

    -- Native debugging (D binaries carry DWARF): codelldb (server) / lldb-dap (executable). The launch
    -- config prompts for the built executable (defaulting under the project root — dub's output dir).
    dap = {
        adapters = {
            codelldb = { kind = "server" },
            ["lldb-dap"] = { kind = "executable" },
        },
        configurations = {
            d = {
                {
                    adapter = "codelldb",
                    request = "launch",
                    name = "Launch (codelldb)",
                    program = "pick",
                    cwd = "${workspaceFolder}",
                    stopOnEntry = false,
                },
                {
                    adapter = "lldb-dap",
                    request = "launch",
                    name = "Launch (lldb-dap)",
                    program = "pick",
                    cwd = "${workspaceFolder}",
                    stopOnEntry = false,
                },
            },
        },
    },

    commands = {
        build = { cmd = { "dub", "build" }, tool = "dub", group = "Build", desc = "dub build" },
        run = { cmd = { "dub", "run" }, tool = "dub", group = "Run", desc = "dub run" },
        test = { cmd = { "dub", "test" }, tool = "dub", group = "Test", desc = "dub test" },
    },

    icons = {
        statusline = "", -- the D marker (nf-dev-dlang)
    },
}
