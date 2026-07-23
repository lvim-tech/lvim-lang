-- lvim-lang.providers.registry.lua: the Lua provider, as declarative DATA (Tier 2).
-- The first language built through the factory (core.declarative). lua-language-server is the LSP; the
-- catalog OFFERS every mason Lua tool so you can pick your default: formatters stylua (default) /
-- luaformatter / emmylua-codeformat; linters luacheck / selene. Debugging: local-lua-debugger-vscode for
-- plain Lua scripts (mason), and the nlua / one-small-step-for-vimkind (osv) attach adapter for debugging
-- a RUNNING Neovim's Lua (start the server with `:lua require('osv').launch({ port = 8086 })`).
-- The Lua runtime (lua / luajit) is the user's own — advisory (the LSP works without it).
--
---@module "lvim-lang.providers.registry.lua"

---@type LvimLangSpecData
return {
    name = "lua",
    filetypes = { "lua" },
    root_patterns = { ".luarc.json", ".luarc.jsonc", "stylua.toml", ".stylua.toml", "selene.toml", ".git" },

    runtime = {
        bin = "lua",
        key = "lua",
        require = false,
        severity = "info",
        label = "Lua runtime",
        hint = "Optional: install lua or luajit to run/test; lua-language-server and the tools work without it.",
    },

    lsp = {
        servers = {
            ["lua-language-server"] = {
                mason = "lua-language-server",
                filetypes = { "lua" },
                settings = {
                    Lua = {
                        diagnostics = { globals = { "vim" } },
                        workspace = { checkThirdParty = false },
                        telemetry = { enable = false },
                        hint = { enable = true }, -- inlay hints
                    },
                },
            },
        },
        default = "lua-language-server",
    },

    ft = {
        lua = {
            formatters = {
                stylua = {
                    mason = "stylua",
                    efm = { formatCommand = "stylua --search-parent-directories -", formatStdin = true },
                },
                -- LuaFormatter (mason `luaformatter`, binary `lua-format`) — reads stdin.
                luaformatter = {
                    mason = "luaformatter",
                    bin = "lua-format",
                    efm = { formatCommand = "lua-format -i", formatStdin = true },
                },
                ["emmylua-codeformat"] = {
                    mason = "emmylua-codeformat",
                    bin = "emmy-codeformat",
                    efm = { formatCommand = "emmy-codeformat format --stdin", formatStdin = true },
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
            debuggers = {
                -- local-lua-debugger-vscode: a node-based DAP for plain Lua scripts (installable).
                ["local-lua-debugger-vscode"] = { mason = "local-lua-debugger-vscode" },
            },
            -- stylua formats; the LSP surfaces diagnostics so no linter is forced on by default.
            defaults = { formatter = "stylua", linter = false, debugger = false },
        },
    },

    -- Debugging. `nlua` attaches to a running Neovim (osv) over TCP; `local-lua` launches a plain Lua
    -- script through the mason local-lua-debugger-vscode (node) adapter.
    dap = {
        adapters = {
            -- Attach to a running Neovim's Lua (one-small-step-for-vimkind / osv serves it on the port).
            nlua = function(cb, cfg)
                cb({ type = "server", host = cfg.host or "127.0.0.1", port = cfg.port or 8086 })
            end,
            -- The mason local-lua-debugger-vscode adapter (node runs its debugAdapter.js).
            ["local-lua"] = function(cb)
                local js = "extension/debugAdapter.js"
                local ok, pkg = pcall(require, "lvim-pkg")
                if ok and type(pkg.bin_dir) == "function" then
                    local pkgdir = vim.fs.normalize(pkg.bin_dir() .. "/../packages/local-lua-debugger-vscode")
                    js = vim.fs.joinpath(pkgdir, js)
                end
                cb({
                    type = "executable",
                    command = vim.fn.exepath("node") ~= "" and "node" or "node",
                    args = { js },
                    enrich_config = function(config, on_config)
                        if not config.extensionPath then
                            config = vim.deepcopy(config)
                            config.extensionPath = "."
                        end
                        on_config(config)
                    end,
                })
            end,
        },
        configurations = {
            lua = {
                {
                    adapter = "nlua",
                    request = "attach",
                    name = "Attach to Neovim (osv, port 8086)",
                    host = "127.0.0.1",
                    port = 8086,
                },
                {
                    adapter = "local-lua",
                    request = "launch",
                    name = "Launch Lua file (local-lua)",
                    program = { lua = "lua", file = "${file}" },
                    cwd = "${workspaceFolder}",
                },
            },
        },
    },

    commands = {
        run = { cmd = { "lua", "${file}" }, tool = "lua", group = "Run", desc = "lua <file>" },
        test = {
            cmd = { "busted" },
            tool = "busted",
            ensure = { mason = "busted" },
            group = "Test",
            desc = "busted — run the Lua test suite",
        },
    },

    icons = {
        statusline = "", -- the Lua marker (nf-seti-lua)
    },
}
