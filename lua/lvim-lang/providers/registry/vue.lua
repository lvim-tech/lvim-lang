-- lvim-lang.providers.registry.vue: the Vue provider (declarative Tier 3 web). vue-language-server (Volar) is the LSP; prettier / rustywind format; eslint_d lints; js-debug (pwa-chrome) debugs. Emmet + Tailwind co-attach as companions.
--
---@module "lvim-lang.providers.registry.vue"

---@type LvimLangSpecData
return {
    name = "vue",
    filetypes = { "vue" },
    root_patterns = { "package.json", "vue.config.js", "vite.config.ts", ".git" },
    lsp = {
        servers = {
            ["vue-language-server"] = {
                mason = "vue-language-server",
                cmd = { "vue-language-server", "--stdio" },
                -- Volar refuses to start without `typescript.tsdk`. A function, so the bundled SDK is
                -- looked up when the server starts: read when this module loaded, it stayed nil for a
                -- server installed by the prompt that opening the buffer raised.
                init_options = require("lvim-lang.core.detect").bundled_tsdk("vue-language-server"),
                filetypes = { "vue" },
            },
        },
        default = "vue-language-server",
    },
    ft = {
        ["vue"] = {
            formatters = {
                ["prettier"] = {
                    mason = "prettier",
                    efm = { formatCommand = "prettier --stdin-filepath ${INPUT}", formatStdin = true },
                },
                ["prettierd"] = {
                    mason = "prettierd",
                    efm = { formatCommand = "prettierd ${INPUT}", formatStdin = true },
                },
                ["rustywind"] = {
                    mason = "rustywind",
                    efm = { formatCommand = "rustywind --stdin", formatStdin = true },
                },
            },
            linters = {
                -- stylish is the one machine-parseable formatter ESLint keeps in core across
                -- versions (unix/compact left core in v9). The %P file-header scope and both
                -- severity rows are probe-verified against efm 0.0.57.
                ["eslint_d"] = {
                    mason = "eslint_d",
                    efm = {
                        lintCommand = "eslint_d --no-color --format stylish --stdin --stdin-filename ${INPUT}",
                        lintStdin = true,
                        lintIgnoreExitCode = true,
                        lintFormats = {
                            "%-P%f",
                            "%*[ ]%l:%c%*[ ]%trror%*[ ]%m",
                            "%*[ ]%l:%c%*[ ]%tarning%*[ ]%m",
                            "%-G%.%#",
                        },
                        rootMarkers = {
                            "eslint.config.js",
                            "eslint.config.mjs",
                            ".eslintrc.js",
                            ".eslintrc.json",
                            "package.json",
                        },
                    },
                },
            },
            -- vue apps run in the browser / node, so they debug through js-debug (pwa-chrome) against
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
            ["vue"] = {
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
    icons = { statusline = "" },
}
