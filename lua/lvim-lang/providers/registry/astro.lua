-- lvim-lang.providers.registry.astro: the Astro provider (declarative Tier 3 web). astro-language-server is the LSP; prettier / rustywind format; eslint_d lints; js-debug (pwa-chrome) debugs. Emmet + Tailwind co-attach as companions.
--
---@module "lvim-lang.providers.registry.astro"

--- The TypeScript SDK bundled with a language-server package. Volar-based servers refuse to start
--- their TS integration without a real `tsdk` path, so this is not optional for them.
--- Resolved through `lvim-pkg.package_path` — NEVER a hardcoded install layout: the previous config
--- hardcoded `~/.local/share/nvim/mason/packages/...`, which silently became a dead path the moment
--- mason was replaced by lvim-pkg, and the setting was dropped in the move instead of ported.
--- Returns nil when the package is not installed, so no bogus path is ever sent.
---@param pkg_name string
---@return string?
local function bundled_tsdk(pkg_name)
    local ok, pkg = pcall(require, "lvim-pkg")
    if not ok or type(pkg.package_path) ~= "function" then
        return nil
    end
    local dir = vim.fs.joinpath(pkg.package_path(pkg_name), "node_modules", "typescript", "lib")
    return vim.fn.isdirectory(dir) == 1 and dir or nil
end

local tsdk = bundled_tsdk("astro-language-server")

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
                -- nil when the package is not installed → the field is simply absent.
                init_options = tsdk and { typescript = { tsdk = tsdk } } or nil,
            },
        },
        default = "astro-language-server",
    },
    ft = {
        ["astro"] = {
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
