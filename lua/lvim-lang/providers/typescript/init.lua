-- lvim-lang.providers.typescript: the TypeScript / JavaScript provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes (typescript / typescriptreact / javascript / javascriptreact), the MULTI-LSP catalog
-- (vtsls for types AND the eslint LSP for diagnostics, both attaching by default), the per-filetype tool
-- catalog (prettier / prettierd / biome / dprint formatters, eslint_d / biome / oxlint linters, the
-- js-debug adapter), the node toolchain, the requirement, health and statusline. This module then
-- EXTENDS the returned spec with JS/TS's project-local resolution — a repo pins its own tools under
-- `node_modules/.bin`, which must win over a shared copy (the analog of Python's venv-awareness):
--   * prettier / tsc / vitest / jest resolve node_modules FIRST; the LSP servers keep mason first with
--     node_modules as a low-priority fallback;
--   * an `eslint-lsp` alias (the eslint server module resolves by the mason package name, not the key);
--   * the npm/pnpm/yarn/bun + vitest/jest command surface (providers.typescript.commands / .tasks / .pm).
--
-- prettier (efm) owns formatting, so both servers' own formatting is switched off on attach
-- (catalog.lsp_on_attach). vtsls / eslint keep their bespoke server-config modules.
--
---@module "lvim-lang.providers.typescript"

local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")
local detect = require("lvim-lang.core.detect")

-- The four filetypes this provider owns.
---@type string[]
local FILETYPES = { "typescript", "typescriptreact", "javascript", "javascriptreact" }

-- The per-filetype catalog block, shared by all four filetypes (deep-copied per ft).
---@type table
local FT_BLOCK = {
    formatters = {
        prettier = {
            mason = "prettier",
            efm = { formatCommand = "prettier --stdin-filepath ${INPUT}", formatStdin = true },
        },
        prettierd = {
            mason = "prettierd",
            efm = { formatCommand = "prettierd ${INPUT}", formatStdin = true },
        },
        biome = {
            mason = "biome",
            efm = { formatCommand = "biome format --stdin-file-path ${INPUT}", formatStdin = true },
        },
        dprint = {
            mason = "dprint",
            efm = { formatCommand = "dprint fmt --stdin ${INPUT}", formatStdin = true },
        },
        oxfmt = { mason = "oxfmt", efm = { formatCommand = "oxfmt --stdin ${INPUT}", formatStdin = true } },
        standardjs = {
            mason = "standardjs",
            bin = "standard",
            efm = { formatCommand = "standard --stdin --fix", formatStdin = true },
        },
        ["ts-standard"] = {
            mason = "ts-standard",
            efm = { formatCommand = "ts-standard --stdin --fix", formatStdin = true },
        },
        -- rustywind sorts Tailwind classes (a formatter for JSX/TSX class lists).
        rustywind = { mason = "rustywind", efm = { formatCommand = "rustywind --stdin", formatStdin = true } },
    },
    linters = {
        eslint_d = {
            mason = "eslint_d",
            efm = {
                lintCommand = "eslint_d --no-color --format compact --stdin --stdin-filename ${INPUT}",
                lintStdin = true,
                lintIgnoreExitCode = true,
                lintFormats = { "%f: line %l, col %c, %trror - %m", "%f: line %l, col %c, %tarning - %m" },
                rootMarkers = { ".eslintrc", ".eslintrc.js", ".eslintrc.cjs", ".eslintrc.json", "eslint.config.js" },
            },
        },
        biome = {
            mason = "biome",
            efm = {
                lintCommand = "biome lint --stdin-file-path ${INPUT}",
                lintStdin = true,
                lintFormats = { "%f:%l:%c %m" },
            },
        },
        oxlint = {
            mason = "oxlint",
            efm = { lintCommand = "oxlint ${INPUT}", lintStdin = false, lintFormats = { "%f:%l:%c %m" } },
        },
        deno = {
            mason = "deno",
            efm = { lintCommand = "deno lint - --json", lintStdin = true, lintFormats = { "%f:%l:%c: %m" } },
        },
        ["quick-lint-js"] = {
            mason = "quick-lint-js",
            efm = {
                lintCommand = "quick-lint-js --stdin --output-format=gnu-like --path-for-config-search ${INPUT}",
                lintStdin = true,
                lintFormats = { "%f:%l:%c: %trror: %m", "%f:%l:%c: %tarning: %m" },
            },
        },
        semgrep = {
            mason = "semgrep",
            efm = {
                lintCommand = "semgrep scan --config auto --quiet --error --disable-version-check --gitlab-sast ${INPUT}",
                lintStdin = false,
                lintFormats = { "%f:%l:%c: %m" },
            },
        },
    },
    debuggers = {
        ["js-debug-adapter"] = { mason = "js-debug-adapter" },
        ["firefox-debug-adapter"] = { mason = "firefox-debug-adapter" },
    },
    defaults = { formatter = "prettier", linter = false, debugger = "js-debug-adapter" },
}

---@type LvimLangSpecData
local DATA = {
    name = "typescript",
    filetypes = FILETYPES,
    root_patterns = { "package.json", "tsconfig.json", "jsconfig.json", ".git" },

    runtime = {
        bin = "node",
        key = "node",
        lookup_key = "node_lookup_cmd",
        managers = { "mise", "asdf", "fnm" },
        require = true,
        label = "Node.js runtime",
        hint = "Install Node.js (e.g. via mise/fnm) and put `node` on PATH; the TypeScript server and eslint run on it.",
    },

    lsp = {
        servers = {
            vtsls = {
                mason = "vtsls",
                bin = "vtsls",
                filetypes = FILETYPES,
                role = "types", -- completion / hover / definition / rename / inlay hints / code actions
                settings = {
                    typescript = {
                        inlayHints = {
                            parameterNames = { enabled = "literals" },
                            parameterTypes = { enabled = true },
                            variableTypes = { enabled = false },
                            propertyDeclarationTypes = { enabled = true },
                            functionLikeReturnTypes = { enabled = true },
                            enumMemberValues = { enabled = true },
                        },
                        updateImportsOnFileMove = { enabled = "always" },
                        preferences = { importModuleSpecifier = "non-relative" },
                    },
                    javascript = {
                        inlayHints = {
                            parameterNames = { enabled = "literals" },
                            parameterTypes = { enabled = true },
                            functionLikeReturnTypes = { enabled = true },
                        },
                    },
                    vtsls = { experimental = { completion = { enableServerSideFuzzyMatch = true } } },
                },
            },
            eslint = {
                mason = "eslint-lsp",
                bin = "vscode-eslint-language-server",
                filetypes = FILETYPES,
                role = "diagnostics", -- eslint lint diagnostics + fix-all code action
                -- vscode-eslint requests its configuration SECTION-LESS, so these live at the TOP LEVEL of
                -- `settings`; the server module injects workspaceFolder / nodePath / useFlatConfig per root.
                settings = {
                    validate = "on",
                    run = "onType",
                    format = false,
                    quiet = false,
                    onIgnoredFiles = "off",
                    packageManager = nil,
                    useESLintClass = false,
                    nodePath = "",
                    rulesCustomizations = {}, -- valid empty ARRAY ([]); an empty OBJECT field would mis-encode
                    problems = { shortenToSingleLine = false },
                    workingDirectory = { mode = "location" },
                    codeActionOnSave = { enable = false, mode = "all" },
                    codeAction = {
                        disableRuleComment = { enable = true, location = "separateLine" },
                        showDocumentation = { enable = true },
                    },
                },
            },
        },
        default = { "vtsls", "eslint" }, -- multi-LSP by default
    },

    ft = {
        typescript = vim.deepcopy(FT_BLOCK),
        typescriptreact = vim.deepcopy(FT_BLOCK),
        javascript = vim.deepcopy(FT_BLOCK),
        javascriptreact = vim.deepcopy(FT_BLOCK),
    },

    icons = {
        statusline = "󰛦", -- the TypeScript marker in the statusline segment
        test = "󰙨",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗",
        script = "󰜎", -- package.json script picker row
        pm = "󰎙", -- package manager (node)
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND: project-local (node_modules/.bin) resolution ────────────────────────────────────────────

--- A tool `bin` inside the project's `node_modules/.bin` (walked up to package.json), if executable —
--- so a project-pinned prettier / eslint / tsc / vitest wins over a shared copy.
---@param bin string
---@return fun(root: string): string|nil
local function in_node_modules(bin)
    return function(root)
        local pkg = vim.fs.root(root, { "package.json" }) or root
        local p = vim.fs.joinpath(pkg, "node_modules", ".bin", bin)
        return vim.fn.executable(p) == 1 and p or nil
    end
end

local tc = spec.toolchain.tools
-- LSP servers keep mason first (editor tools), with a project-local copy as a low-priority fallback.
table.insert(tc.vtsls, #tc.vtsls, { kind = "path", value = in_node_modules("vtsls") })
-- The eslint server module resolves by the mason package name, not the catalog key — alias it.
tc["eslint-lsp"] = tc.eslint
-- prettier is PROJECT-LOCAL first (a repo pins its formatter), then mason, then PATH.
table.insert(tc.prettier, 2, { kind = "path", value = in_node_modules("prettier") })
-- tsc / vitest / jest are project dev-dependencies the commands invoke: node_modules → mason → PATH.
tc.tsc = {
    { kind = "path", value = in_node_modules("tsc") },
    { kind = "path", value = detect.in_mason("tsc") },
    { kind = "which", value = "tsc" },
}
tc.vitest = {
    { kind = "path", value = in_node_modules("vitest") },
    { kind = "which", value = "vitest" },
}
tc.jest = {
    { kind = "path", value = in_node_modules("jest") },
    { kind = "which", value = "jest" },
}

-- Extra provider config the commands / pm / test modules read.
defaults.package_manager = "auto" -- "auto" detects (lockfile / corepack); pin to npm|pnpm|yarn|bun
defaults.test_runner = "auto" -- "auto" detects vitest / jest; pin to one
defaults.codegen = {} -- `:LvimLang types` emits `.d.ts` via tsc (resolved through the toolchain)

spec.commands = require("lvim-lang.providers.typescript.commands")
spec.tasks = require("lvim-lang.providers.typescript.tasks").templates

registry.register(spec, defaults)

return spec
