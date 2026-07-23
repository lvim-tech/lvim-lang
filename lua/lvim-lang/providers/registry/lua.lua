-- lvim-lang.providers.registry.lua: the Lua provider, as declarative DATA (Tier 2).
-- The first language built through the factory (core.declarative) — no bespoke module, just this record.
-- lua-language-server is the LSP; stylua the default formatter (routed through efm so the LSP hands off
-- formatting); luacheck / selene are opt-in linters; busted the test runner (installed on demand the
-- first time :LvimLang test runs). The Lua runtime (lua / luajit) is the user's own and only advisory —
-- the language server needs no external runtime — so it is surfaced as an INFO requirement.
--
---@module "lvim-lang.providers.registry.lua"

---@type LvimLangSpecData
return {
    name = "lua",
    filetypes = { "lua" },
    root_patterns = { ".luarc.json", ".luarc.jsonc", "stylua.toml", ".stylua.toml", "selene.toml", ".git" },

    -- Advisory only: lua-language-server / stylua work without a system Lua; running tests wants one.
    runtime = {
        bin = "lua",
        key = "lua",
        label = "Lua runtime",
        hint = "Optional: install lua or luajit to run/test; lua-language-server and stylua work without it.",
        severity = "info",
    },

    lsp = {
        servers = {
            ["lua-language-server"] = {
                mason = "lua-language-server",
                filetypes = { "lua" },
                -- Overridable / extendable through setup({ providers = { lua = { lsp = { servers = … } } } }).
                settings = {
                    Lua = {
                        diagnostics = { globals = { "vim" } },
                        workspace = { checkThirdParty = false },
                        telemetry = { enable = false },
                    },
                },
            },
        },
        default = "lua-language-server",
    },

    ft = {
        lua = {
            formatters = {
                -- stylua reads stdin (`-`) and honours the nearest stylua.toml.
                stylua = {
                    mason = "stylua",
                    efm = { formatCommand = "stylua --search-parent-directories -", formatStdin = true },
                },
            },
            linters = {
                luacheck = {
                    mason = "luacheck",
                    efm = {
                        lintCommand = "luacheck --formatter plain --codes --ranges --filename ${INPUT} -",
                        lintStdin = true,
                        lintFormats = { "%f:%l:%c: %m" },
                    },
                },
                selene = {
                    mason = "selene",
                    efm = {
                        lintCommand = "selene --display-style quiet -",
                        lintStdin = true,
                        lintFormats = { "%f:%l:%c: %t%*[^:]: %m" },
                    },
                },
            },
            debuggers = {},
            -- stylua formats; the LSP surfaces diagnostics so no linter is forced on by default.
            defaults = { formatter = "stylua", linter = false, debugger = false },
        },
    },

    commands = {
        test = {
            cmd = { "busted" },
            tool = "busted",
            ensure = { mason = "busted" }, -- installed on demand the first time this runs
            group = "Test",
            desc = "busted — run the Lua test suite",
        },
    },

    icons = {
        statusline = "", -- the Lua marker in the statusline segment (Nerd Font)
    },
}
