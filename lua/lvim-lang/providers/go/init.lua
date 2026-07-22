-- lvim-lang.providers.go: the Go provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Built milestone by milestone;
-- G0 wires the toolchain (go/gopls/dlv resolution), a health section and a statusline segment.
-- LSP (gopls), the per-filetype formatter/linter catalog, tasks, DAP (delve) and codegen follow.
--
-- CANONICAL per-filetype model: one provider covers several filetypes (go / gomod / gowork /
-- gotmpl); each carries its OWN catalog of formatters / linters / debuggers with sane defaults,
-- while a single LSP server (gopls) attaches to all of them. The whole tool catalog below is
-- DERIVED from the mason registry (languages = Go, categories = Formatter / Linter / DAP);
-- the user just picks a default per filetype (or `false` for none) and may override any setting.
--
---@module "lvim-lang.providers.go"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.core.toolchain")

-- Per-language defaults, merged into config.providers.go at registration (users override via
-- setup({ providers = { go = { … } } })).
---@type table
local DEFAULTS = {
    -- Explicit binary paths; when set each wins over every other resolution strategy.
    go_path = nil,
    gopls_path = nil,
    dlv_path = nil,
    -- A shell command whose first output line is the `go` binary path (checked after go_path,
    -- before the version manager / PATH). Empty by default.
    go_lookup_cmd = nil,
    -- Version manager for the `go` toolchain: "mise" | "asdf" | false (ignore) | function(root).
    -- Honours the project's pinned Go version. Default: try mise then asdf, else PATH.
    version_manager = nil,

    -- LSP server catalog. Every suitable server (mason registry, languages = Go, category = LSP)
    -- with its default settings; `default` selects which attach — a STRING or a LIST (several LSP
    -- clients attach to the same buffer, e.g. gopls for types + a linter LSP for diagnostics).
    -- `role` coordinates overlapping capabilities when more than one server runs.
    lsp = {
        servers = {
            gopls = {
                mason = "gopls",
                filetypes = { "go", "gomod", "gowork", "gotmpl" },
                role = "types", -- completion / hover / definition / rename / inlay hints
                settings = {
                    gopls = {
                        hints = {
                            assignVariableTypes = true,
                            compositeLiteralFields = true,
                            constantValues = true,
                            functionTypeParameters = true,
                            parameterNames = true,
                            rangeVariableTypes = true,
                        },
                        analyses = {
                            unusedparams = true,
                            shadow = true,
                            nilness = true,
                            unusedwrite = true,
                            useany = true,
                        },
                        staticcheck = true,
                        gofumpt = true,
                        semanticTokens = true,
                        usePlaceholders = true,
                        completeUnimported = true,
                        codelenses = {
                            generate = true,
                            gc_details = true,
                            test = true,
                            tidy = true,
                            upgrade_dependency = true,
                            regenerate_cgo = true,
                            run_govulncheck = true,
                            vendor = true,
                        },
                    },
                },
            },
            ["golangci-lint-langserver"] = {
                mason = "golangci-lint-langserver",
                filetypes = { "go" },
                role = "diagnostics", -- alternative to the efm golangci-lint linter
                -- Requires the golangci-lint binary; its command is set in the server config.
                settings = {},
            },
        },
        default = "gopls", -- string | string[]; add "golangci-lint-langserver" for LSP-based linting
    },

    -- Per-FILETYPE catalog: formatters / linters / debuggers available for each ft, each with a
    -- default configuration, plus which one is the `default` (or false = none). Only the CHOSEN
    -- tools are installed (their mason package is contributed to the installer) and wired (through
    -- efm-langserver, which routes per filetype). Every entry is fully overridable via
    -- setup({ providers = { go = { ft = { go = { formatter = "goimports" } } } } }).
    ft = {
        go = {
            formatters = {
                gofumpt = { mason = "gofumpt", efm = { formatCommand = "gofumpt", formatStdin = true } },
                goimports = { mason = "goimports", efm = { formatCommand = "goimports", formatStdin = true } },
                golines = { mason = "golines", efm = { formatCommand = "golines --max-len=120", formatStdin = true } },
                gci = { mason = "gci", efm = { formatCommand = "gci print", formatStdin = true } },
                ["goimports-reviser"] = {
                    mason = "goimports-reviser",
                    efm = { formatCommand = "goimports-reviser -output stdout ${INPUT}", formatStdin = false },
                },
            },
            linters = {
                ["golangci-lint"] = {
                    mason = "golangci-lint",
                    efm = {
                        lintCommand = "golangci-lint run --output.text.path stdout --show-stats=false --output.text.print-issued-lines=false",
                        lintStdin = false,
                        lintFormats = { "%f:%l:%c: %m" },
                        rootMarkers = { ".golangci.yml", ".golangci.yaml", ".golangci.toml", ".golangci.json" },
                    },
                },
                revive = {
                    mason = "revive",
                    efm = { lintCommand = "revive ${INPUT}", lintStdin = false, lintFormats = { "%f:%l:%c: %m" } },
                },
                staticcheck = {
                    mason = "staticcheck",
                    efm = { lintCommand = "staticcheck ${INPUT}", lintStdin = false, lintFormats = { "%f:%l:%c: %m" } },
                },
            },
            debuggers = {
                delve = { mason = "delve", bin = "dlv" },
                ["go-debug-adapter"] = { mason = "go-debug-adapter" },
            },
            -- No default efm formatter: gopls formats Go natively (gofumpt = true in its settings),
            -- so a separate formatter is redundant. The catalog still OFFERS gofumpt/goimports/… for
            -- users who prefer efm-based formatting (set ft.go.formatter = "goimports", etc.).
            defaults = { formatter = false, linter = "golangci-lint", debugger = "delve" },
        },
        gomod = {
            -- go.mod concerns: gopls handles most; golangci-lint's module directives are opt-in.
            linters = {
                ["golangci-lint"] = {
                    mason = "golangci-lint",
                    efm = {
                        lintCommand = "golangci-lint run --output.text.path stdout --show-stats=false --output.text.print-issued-lines=false",
                        lintStdin = false,
                        lintFormats = { "%f:%l:%c: %m" },
                    },
                },
            },
            defaults = { linter = false },
        },
        gowork = {
            defaults = {},
        },
        gotmpl = {
            defaults = {},
        },
    },

    -- Codegen tools (invoked as :LvimLang tags/gotests/impl). ON-DEMAND by default — installed the
    -- first time you run their command (core.ensure). Set `active = true` on any of them to install it
    -- UPFRONT instead, in the same file-open installer popup as the LSP/formatter/linter/debugger.
    codegen = {
        gomodifytags = { mason = "gomodifytags" }, -- add `active = true` to install upfront
        gotests = { mason = "gotests" },
        impl = { mason = "impl" },
    },

    -- Nerd Font icons used in the Go provider's pickers / statusline (all configurable).
    icons = {
        statusline = "", -- the Go marker in the statusline segment
        test = "", -- test runner / result row
        build = "", -- build task row
        run = "󰐊", -- run task row
        debug = "", -- debug session row
        mod = "", -- go.mod / dependency row
        tags = "󰓹", -- struct-tag codegen row
    },
}

--- Health section for :checkhealth lvim-lang: report whether the Go toolchain resolves for the
--- current working directory, and at what version.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."
    for _, tool in ipairs({ "go", "gopls", "dlv" }) do
        local path, reason = toolchain.resolve("go", tool, root)
        if path then
            local ver = toolchain.version("go", tool, root)
            h.ok(("%s: %s%s"):format(tool, path, ver and ("  (" .. ver .. ")") or ""))
        elseif tool == "go" then
            h.warn(("go not found — %s"):format(reason or "no strategy matched"))
        else
            h.info(("%s not found — installed on demand from the mason registry"):format(tool))
        end
    end
end

--- Statusline segment for a root: the Go marker + the active run config (if any). Kept minimal
--- until run configs land (G8).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.go and config.providers.go.icons) or {}
    local parts = { ic.statusline or "" }
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
    name = "go",
    filetypes = { "go", "gomod", "gowork", "gotmpl" },
    root_patterns = { "go.work", "go.mod", ".git" },
    statusline = statusline,
    toolchain = require("lvim-lang.providers.go.toolchain"),
    commands = require("lvim-lang.providers.go.commands"),
    -- lvim-tasks templates (arg-less go mod subcommands) — also runnable via :LvimLang mod.
    tasks = require("lvim-lang.providers.go.mod").templates,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
