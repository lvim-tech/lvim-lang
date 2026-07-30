-- lvim-lang.providers.registry.lua: the Lua provider, as declarative DATA (Tier 2).
-- The first language built through the factory (core.declarative). lua-language-server is the LSP; the
-- catalog OFFERS every mason Lua tool so you can pick your default: formatters stylua (default) /
-- luaformatter / emmylua-codeformat; linters luacheck / selene. Debugging: local-lua-debugger-vscode for
-- plain Lua scripts (mason), and the nlua / one-small-step-for-vimkind (osv) attach adapter for debugging
-- a RUNNING Neovim's Lua (start the server with `:lua require('osv').launch({ port = 8086 })`).
-- The Lua runtime (lua / luajit) is the user's own — advisory (the LSP works without it).
--
---@module "lvim-lang.providers.registry.lua"

-- ── which interpreter runs THIS Lua file ─────────────────────────────────────
-- A Lua file in this editor is one of two different languages sharing a syntax: a plain Lua script,
-- which the standalone interpreter runs, and NEOVIM Lua, which only means anything inside Neovim (it
-- reads the `vim` global). Handing the second to `lua` fails on its first line —
-- `attempt to index a nil value (global 'vim')` — so the `run` command picks the interpreter from the
-- FILE rather than assuming one. `nvim -l <file>` is Neovim's own script mode: it runs the file in
-- Neovim's Lua with the full API and without loading the user config.

--- Whether `path` is `dir` itself or sits inside it (both already normalised).
---@param path string
---@param dir string
---@return boolean
local function under(path, dir)
    return path == dir or path:sub(1, #dir + 1) == dir .. "/"
end

--- Whether `file` belongs to the EDITOR'S OWN configuration — `stdpath("config")` or any extra XDG
--- config dir. Nothing there is a standalone script: every file is a module the editor itself loads,
--- so running one as a separate process is never what the user means, and it is one of two measured
--- outcomes. `nvim -l init.lua` exits 0 having loaded the WHOLE config a second time — writing to the
--- state it shares with the running editor (the lvim-space / control-center sqlite databases, the
--- active theme, the keys-helper cache), which is a concurrent-write hazard, not a dry run. Any other
--- file there is a module that expects to be `require`d and dies with exit 1.
--- Plugin modules on the runtimepath are deliberately NOT covered: they only ever exit 1 with
--- Neovim's own self-explanatory error, they touch nothing, and a plugin repo legitimately holds real
--- scripts (a probe / a test harness) that `nvim -l` should keep running.
---@param file string
---@return boolean
local function is_editor_config(file)
    if file == "" then
        return false
    end
    local path = vim.fs.normalize(file)
    local dirs = { vim.fn.stdpath("config") }
    vim.list_extend(dirs, vim.fn.stdpath("config_dirs") --[[@as string[] ]])
    for _, dir in ipairs(dirs) do
        if under(path, vim.fs.normalize(dir)) then
            return true
        end
    end
    return false
end

--- Whether `file` is NEOVIM Lua. Two signals, in order of authority:
---  1. it lives under a `runtimepath` entry — the config, the data dir, any installed plugin. This is
---     structural, not a guess: everything there is loaded BY Neovim and is Neovim Lua by definition.
---  2. it references the `vim` global. This catches Neovim Lua that lives outside the runtimepath —
---     a project's `.lvim/` config, a scratch script poking at the API — where nothing but the
---     content can tell. Only the head of the file is read (a `vim.` past that would be unusual, and
---     this runs on every `run`).
---@param file string
---@return boolean
local function is_nvim_lua(file)
    if file == "" then
        return false
    end
    local path = vim.fs.normalize(file)
    for _, rtp in ipairs(vim.api.nvim_list_runtime_paths()) do
        if under(path, vim.fs.normalize(rtp)) then
            return true
        end
    end
    local ok, lines = pcall(vim.fn.readfile, file, "", 200)
    if ok then
        for _, line in ipairs(lines) do
            -- `vim.x` / `vim[…]` as a whole word — not `mvim.`, not the word inside a comment's prose
            if line:match("^vim%s*[%.%[]") or line:match("[^%w_]vim%s*[%.%[]") then
                return true
            end
        end
    end
    return false
end

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
        -- A BUILDER, not an argv template: the interpreter depends on the file (see is_nvim_lua).
        run = {
            cmd = function(ctx)
                if ctx.file == "" then
                    vim.notify("lvim-lang: no file in this buffer to run", vim.log.levels.WARN, { title = "lvim-lang" })
                    return nil
                end
                -- Checked BEFORE the interpreter split: a config file is always Neovim Lua, and the
                -- point is that no interpreter is the right answer for it (see is_editor_config).
                if is_editor_config(ctx.file) then
                    vim.notify(
                        ("%s belongs to this editor's configuration — running it as a script would load the whole config a second time and write to state it shares with the running editor (session / control-center databases, the active theme). Use `:source %%` to apply it here, or restart."):format(
                            vim.fn.fnamemodify(ctx.file, ":~:.")
                        ),
                        vim.log.levels.WARN,
                        { title = "lvim-lang" }
                    )
                    return nil
                end
                if is_nvim_lua(ctx.file) then
                    -- Neovim's own binary — always present, so nothing to resolve through the toolchain.
                    return { vim.v.progpath, "-l", ctx.file }
                end
                local bin = require("lvim-lang.core.toolchain").resolve("lua", "lua", ctx.root)
                if not bin then
                    vim.notify(
                        "lvim-lang: no Lua interpreter found — install lua or luajit and put it on PATH",
                        vim.log.levels.WARN,
                        { title = "lvim-lang" }
                    )
                    return nil
                end
                return { bin, ctx.file }
            end,
            group = "Run",
            desc = "run the file (nvim -l for Neovim Lua, else the Lua interpreter)",
        },
        test = {
            cmd = { "busted" },
            tool = "busted",
            -- busted is a LuaRocks rock and is NOT in the mason registry, so asking the registry
            -- for it installed nothing and reported only that no binary appeared.
            ensure = { luarocks = "busted" },
            group = "Test",
            desc = "busted — run the Lua test suite",
        },
    },

    icons = {
        statusline = "", -- the Lua marker (nf-seti-lua)
    },
}
