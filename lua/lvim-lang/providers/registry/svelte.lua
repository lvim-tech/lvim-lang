-- lvim-lang.providers.registry.svelte: the Svelte provider (declarative Tier 3 web). svelte-language-server is the LSP; prettier / rustywind format; eslint_d lints; js-debug (pwa-chrome) debugs. Emmet + Tailwind co-attach as companions.
--
---@module "lvim-lang.providers.registry.svelte"

---@type LvimLangSpecData
return {
    name = "svelte",
    filetypes = { "svelte" },
    root_patterns = { "package.json", "svelte.config.js", ".git" },
    lsp = {
        servers = {
            ["svelte-language-server"] = {
                mason = "svelte-language-server",
                bin = "svelteserver",
                cmd = { "svelteserver", "--stdio" },
                filetypes = { "svelte" },
            },
        },
        default = "svelte-language-server",
    },
    ft = {
        ["svelte"] = {
            formatters = {
                ["prettier"] = { mason = "prettier" },
                ["prettierd"] = { mason = "prettierd" },
                ["rustywind"] = { mason = "rustywind" },
            },
            linters = { ["eslint_d"] = { mason = "eslint_d" } },
            -- svelte apps run in the browser / node, so they debug through js-debug (pwa-chrome) against
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
            ["svelte"] = {
                {
                    adapter = "pwa-chrome",
                    request = "launch",
                    name = "Launch Chrome against the dev server",
                    url = "http://localhost:5173",
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
    icons = { statusline = "" },
}
