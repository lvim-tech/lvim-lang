-- lvim-lang.providers.registry.elm: the Elm provider (declarative Tier 2).
-- elm-language-server is the LSP; elm-format is the formatter (mason, efm). `elm make` builds; `elm-test`
-- runs the tests. Elm compiles to JavaScript, so no native debugger.
--
---@module "lvim-lang.providers.registry.elm"

---@type LvimLangSpecData
return {
    name = "elm",
    filetypes = { "elm" },
    root_patterns = { "elm.json", ".git" },
    runtime = {
        bin = "elm",
        key = "elm",
        require = true,
        label = "Elm",
        hint = "Install Elm (https://guide.elm-lang.org/install/elm.html) and put `elm` on PATH.",
    },
    lsp = {
        servers = { ["elm-language-server"] = { mason = "elm-language-server", filetypes = { "elm" } } },
        default = "elm-language-server",
    },
    ft = {
        elm = {
            formatters = {
                ["elm-format"] = {
                    mason = "elm-format",
                    efm = { formatCommand = "elm-format --stdin", formatStdin = true },
                },
            },
            linters = {},
            defaults = { formatter = "elm-format", linter = false },
        },
    },
    commands = {
        -- The entry module is found through elm.json's `source-directories` (first `<dir>/Main.elm`
        -- that exists), else the current .elm file — not a hard-coded src/Main.elm.
        build = {
            cmd = function(ctx)
                local ok, json = pcall(vim.fn.readfile, ctx.root .. "/elm.json")
                if ok then
                    local dec_ok, data = pcall(vim.json.decode, table.concat(json, "\n"))
                    local dirs = dec_ok and type(data) == "table" and data["source-directories"] or nil
                    for _, dir in ipairs(type(dirs) == "table" and dirs or {}) do
                        local rel = dir .. "/Main.elm"
                        if vim.uv.fs_stat(ctx.root .. "/" .. rel) then
                            return { "elm", "make", rel }
                        end
                    end
                end
                if ctx.file ~= "" and ctx.file:match("%.elm$") then
                    return { "elm", "make", ctx.file }
                end
                vim.notify("lvim-lang: no Main.elm found under elm.json's source-directories and no .elm buffer to build", vim.log.levels.WARN, { title = "lvim-lang" })
                return nil
            end,
            tool = "elm",
            group = "Build",
            desc = "elm make <source-directories>/Main.elm",
        },
        test = { cmd = { "elm-test" }, ensure = { mason = "elm-test" }, group = "Test", desc = "elm-test" },
    },
    icons = { statusline = "" }, -- Elm
}
