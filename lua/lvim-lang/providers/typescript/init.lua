-- lvim-lang.providers.typescript: the TypeScript / JavaScript provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). One provider covers all four JS/TS
-- filetypes (typescript, typescriptreact, javascript, javascriptreact). Reuses the shared core: the
-- per-filetype catalog (core.catalog), the multi-LSP fan-out (core.lsp.register_catalog) and
-- on-demand tooling (core.ensure).
--
-- Like Python, the default LSP is a LIST: `vtsls` (types / hover / completion / code actions) AND the
-- `eslint` language server (lint diagnostics + fix-all) attach to the same buffer; `prettier` (efm)
-- owns formatting, so both servers' own formatting is switched off automatically (an efm formatter is
-- active). The whole toolchain is PROJECT-LOCAL first (providers.typescript.toolchain resolves
-- node_modules/.bin before mason / PATH), and the package manager (npm / pnpm / yarn / bun) is
-- detected per project (providers.typescript.pm).
--
---@module "lvim-lang.providers.typescript"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.providers.typescript.toolchain")
local core_toolchain = require("lvim-lang.core.toolchain")
local requirements = require("lvim-lang.core.requirements")

-- The four filetypes this provider owns.
---@type string[]
local FILETYPES = { "typescript", "typescriptreact", "javascript", "javascriptreact" }

--- Turn OFF an LSP client capability once (per-client, so it covers every buffer of that client).
---@param client table  the LSP client (server_capabilities toggled in place)
---@param cap string    server_capabilities key
---@return nil
local function disable_cap(client, cap)
    if client.server_capabilities then
        client.server_capabilities[cap] = false
    end
end

-- The per-filetype catalog block, shared by all four filetypes (deep-copied per ft at register).
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
    },
    debuggers = {
        ["js-debug-adapter"] = { mason = "js-debug-adapter" },
    },
    -- prettier formats (efm); the eslint LSP lints (so no default efm linter); js-debug debugs.
    defaults = { formatter = "prettier", linter = false, debugger = "js-debug-adapter" },
}

---@type table
local DEFAULTS = {
    -- Explicit binary paths; each wins over every other resolution strategy.
    node_path = nil,
    vtsls_path = nil,
    eslint_lsp_path = nil,
    prettier_path = nil,
    node_lookup_cmd = nil, -- shell command whose first line is the `node` path
    -- Version manager for node: "mise" | "asdf" | "fnm" | false | function(root).
    -- Honours a project's pin (.nvmrc / .tool-versions). Default: mise → asdf → fnm → PATH.
    version_manager = nil,

    -- LSP server catalog. The default is a LIST — vtsls (types) AND the eslint LSP (lint + fix).
    -- Set `lsp.server = "vtsls"` to run a single server (or "ts_ls" via a custom entry).
    lsp = {
        servers = {
            vtsls = {
                mason = "vtsls",
                bin = "vtsls",
                filetypes = FILETYPES,
                role = "types", -- completion / hover / definition / rename / inlay hints / code actions
                settings = {
                    -- vtsls forwards these to tsserver; inlay hints for both TS and JS.
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
                -- prettier owns formatting; the eslint LSP only lints / fixes. vscode-eslint requests
                -- its configuration SECTION-LESS, so these live at the TOP LEVEL of `settings` (not
                -- nested under `eslint`); the server module injects `workspaceFolder` / `nodePath` /
                -- `experimental.useFlatConfig` per project root (they must be defined, else the server
                -- throws "path … undefined" on textDocument/diagnostic).
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

    -- `:LvimLang types` emits `.d.ts` via tsc (resolved through the toolchain) — no upfront install.
    codegen = {},

    -- Package manager: "auto" detects it (lockfile / corepack); pin to "npm"|"pnpm"|"yarn"|"bun".
    package_manager = "auto",

    -- Test runner: "auto" detects vitest / jest (config / devDependency / test script); pin to one.
    test_runner = "auto",

    -- Statusline / picker icons (Nerd Font, all configurable).
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

--- Health section for :checkhealth lvim-lang: node, the language servers, prettier and the detected
--- package manager, for the current working directory.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."

    local node = core_toolchain.resolve("typescript", "node", root)
    if node then
        local ver = core_toolchain.version("typescript", "node", root)
        h.ok(("node: %s%s"):format(node, ver and ("  (" .. ver .. ")") or ""))
    else
        h.warn("node not found — install Node.js or set providers.typescript.node_path")
    end

    for _, tool in ipairs({ "vtsls", "eslint-lsp", "prettier" }) do
        local path = core_toolchain.resolve("typescript", tool, root)
        if path then
            h.ok(("%s: %s"):format(tool, path))
        else
            h.info(("%s not found — installed on demand from the mason registry (or node_modules)"):format(tool))
        end
    end

    h.info("package manager: " .. require("lvim-lang.providers.typescript.pm").detect(root))
end

--- Statusline segment for a root: the TS marker + the package manager + the active run config.
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.typescript and config.providers.typescript.icons) or {}
    local parts = { ic.statusline or "" }
    parts[#parts + 1] = require("lvim-lang.providers.typescript.pm").detect(root)
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
    name = "typescript",
    filetypes = FILETYPES,
    root_patterns = { "package.json", "tsconfig.json", "jsconfig.json", ".git" },
    statusline = statusline,
    toolchain = toolchain,
    commands = require("lvim-lang.providers.typescript.commands"),
    -- lvim-tasks templates (install / arg-less scripts) — also via :LvimLang install / script.
    tasks = require("lvim-lang.providers.typescript.tasks").templates,
    --- Surfaced at activation + in :checkhealth: Node.js must be present (the server + eslint run on it).
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
        return {
            requirements.tool_present(
                "typescript",
                "node",
                "Node.js runtime",
                "Install Node.js (e.g. via mise/fnm) and put `node` on PATH; the TypeScript server and eslint "
                    .. "run on it.",
                root
            ),
        }
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
