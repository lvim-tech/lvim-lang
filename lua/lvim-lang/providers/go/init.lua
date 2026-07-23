-- lvim-lang.providers.go: the Go provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes (go / gomod / gowork / gotmpl), the gopls (default) + golangci-lint-langserver (opt-in)
-- LSP catalog, the per-filetype tool catalog (gofumpt / goimports / … formatters, golangci-lint / revive /
-- staticcheck linters, delve / go-debug-adapter debuggers), the go toolchain, the requirement, health and
-- statusline. This module then EXTENDS the returned spec with Go's idiosyncratic parts:
--   * the version prober is DATA (Go CLIs use the `version` SUBCOMMAND, not `--version`);
--   * gopls / dlv resolved from the `go install` bin dir (`go env GOBIN` / `GOPATH/bin`) before PATH;
--   * the on-demand codegen tools (gomodifytags / gotests / impl) seeded into the config;
--   * the go build/run/test + go mod + delve command surface (providers.go.commands / .tasks / .mod / .dap).
--
-- gopls formats Go natively (gofumpt = true) so the efm formatter defaults off. gopls keeps its bespoke
-- servers/gopls.lua; golangci-lint-langserver (no bespoke file) is served by the factory's generic shim.
--
---@module "lvim-lang.providers.go"

local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")
local core_toolchain = require("lvim-lang.core.toolchain")

---@type LvimLangSpecData
local DATA = {
    name = "go",
    filetypes = { "go", "gomod", "gowork", "gotmpl" },
    root_patterns = { "go.work", "go.mod", ".git" },

    runtime = {
        bin = "go",
        key = "go",
        lookup_key = "go_lookup_cmd",
        require = true,
        label = "Go toolchain",
        hint = "Install Go and put `go` on PATH (or set providers.go.bin_paths.go); gopls needs the go command + GOROOT.",
    },
    -- Go CLIs (go / gopls / dlv) use the `version` SUBCOMMAND (not `--version`); take the first line.
    version = function(bin)
        local out = vim.fn.systemlist({ bin, "version" })
        if vim.v.shell_error ~= 0 or type(out) ~= "table" then
            return nil
        end
        for _, line in ipairs(out) do
            local trimmed = vim.trim(line)
            if trimmed ~= "" then
                return trimmed
            end
        end
        return nil
    end,

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
                settings = {},
            },
        },
        default = "gopls", -- string | string[]; add "golangci-lint-langserver" for LSP-based linting
    },

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
            -- gopls formats Go natively → no default efm formatter; the catalog still OFFERS gofumpt/….
            defaults = { formatter = false, linter = "golangci-lint", debugger = "delve" },
        },
        gomod = {
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
        gowork = { defaults = {} },
        gotmpl = { defaults = {} },
    },

    icons = {
        statusline = "󰟓", -- the Go marker in the statusline segment
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        mod = "󰏗", -- go.mod / dependency row
        tags = "󰓹", -- struct-tag codegen row
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND ─────────────────────────────────────────────────────────────────────────────────────────

--- The directory `go install` drops binaries into: `go env GOBIN`, else `go env GOPATH`/bin.
---@param root string
---@return string|nil
local function go_bin_dir(root)
    local go = core_toolchain.resolve("go", "go", root)
    if not go then
        return nil
    end
    local function go_env(key)
        local out = vim.system({ go, "env", key }, { cwd = root, text = true }):wait()
        if out.code ~= 0 then
            return nil
        end
        local v = vim.trim(out.stdout or "")
        return v ~= "" and v or nil
    end
    local gobin = go_env("GOBIN")
    if gobin then
        return gobin
    end
    local gopath = go_env("GOPATH")
    return gopath and vim.fs.joinpath(gopath, "bin") or nil
end

--- A Go-installed tool `bin` inside the resolved `go install` bin dir, or nil.
---@param bin string
---@return fun(root: string): string|nil
local function in_go_bin(bin)
    return function(root)
        local dir = go_bin_dir(root)
        if not dir then
            return nil
        end
        local path = vim.fs.joinpath(dir, bin)
        return vim.fn.executable(path) == 1 and path or nil
    end
end

local tc = spec.toolchain.tools
-- gopls / dlv are `go install` binaries: prefer the go bin dir before the mason / PATH fallbacks.
table.insert(tc.gopls, 2, { kind = "path", value = in_go_bin("gopls") })
-- Commands resolve the debugger by its BINARY name `dlv` (the ft catalog keys it "delve"); add it.
tc.dlv = {
    { kind = "path", value = require("lvim-lang.core.detect").explicit("go", "dlv") },
    { kind = "path", value = in_go_bin("dlv") },
    { kind = "which", value = "dlv" },
}

-- Codegen tools (:LvimLang tags/gotests/impl) — ON-DEMAND by default (installed the first time their
-- command runs); set `active = true` on any to install it upfront in the file-open installer popup.
defaults.codegen = {
    gomodifytags = { mason = "gomodifytags" },
    gotests = { mason = "gotests" },
    impl = { mason = "impl" },
}

spec.commands = require("lvim-lang.providers.go.commands")
-- lvim-tasks templates (arg-less go mod subcommands) — also runnable via :LvimLang mod.
spec.tasks = require("lvim-lang.providers.go.mod").templates

registry.register(spec, defaults)

return spec
