-- lvim-lang.providers.registry.astro: the Astro provider (declarative Tier 3 web). astro-language-server is the LSP; prettier / rustywind format; eslint_d lints; js-debug (pwa-chrome) debugs. Emmet + Tailwind co-attach as companions.
--
---@module "lvim-lang.providers.registry.astro"

---@type LvimLangSpecData
return {
    name = "astro",
    filetypes = { "astro" },
    root_patterns = { "package.json", "astro.config.mjs", "astro.config.ts", ".git" },
    lsp = {
        servers = {
            ["astro-language-server"] = {
                mason = "astro-language-server",
                bin = "astro-ls",
                cmd = { "astro-ls", "--stdio" },
                filetypes = { "astro" },
            },
        },
        default = "astro-language-server",
    },
    ft = {
        ["astro"] = {
            formatters = {
                ["prettier"] = { mason = "prettier" },
                ["prettierd"] = { mason = "prettierd" },
                ["rustywind"] = { mason = "rustywind" },
            },
            linters = { ["eslint_d"] = { mason = "eslint_d" } },
            -- astro apps run in the browser / node, so they debug through js-debug (pwa-chrome) against
            -- the running dev server — firefox-debug-adapter is the Firefox alternative.
            debuggers = {
                ["js-debug-adapter"] = { mason = "js-debug-adapter" },
                ["firefox-debug-adapter"] = { mason = "firefox-debug-adapter" },
            },
            defaults = { formatter = false, linter = false, debugger = "js-debug-adapter" },
        },
    },
    -- Browser debugging: js-debug starts a DAP server (`js-debug-adapter <port>`) and serves the
    -- "pwa-chrome" launch type; the config points at this framework's dev-server URL + webRoot.
    dap = {
        adapters = {
            ["pwa-chrome"] = { kind = "server", tool = "js-debug-adapter", args = { "${port}" } },
        },
        configurations = {
            ["astro"] = {
                {
                    adapter = "pwa-chrome",
                    request = "launch",
                    name = "Launch Chrome against the dev server",
                    url = "http://localhost:4321",
                    webRoot = "${workspaceFolder}",
                    sourceMaps = true,
                },
            },
        },
    },
    commands = {
        build = { cmd = { "npm", "run", "build" }, tool = "npm", group = "Build", desc = "npm run build" },
        dev = { cmd = { "npm", "run", "dev" }, tool = "npm", group = "Run", desc = "npm run dev" },
    },
    icons = { statusline = "󰿶" },
}
