-- lvim-lang.providers.python: the Python provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Reuses the Go/Rust core: the
-- per-filetype catalog (core.catalog), the multi-LSP fan-out (core.lsp.register_catalog) and
-- on-demand tooling (core.ensure).
--
-- Python is the FIRST provider whose default LSP is a LIST rather than a string: `basedpyright`
-- (types / hover / completion / inlay hints) AND `ruff` (lint diagnostics + format + organize
-- imports) attach to the SAME buffer, each owning what it is best at — so their server entries
-- coordinate (basedpyright yields formatting to ruff; ruff yields hover to basedpyright). Because
-- ruff-the-LSP owns formatting and linting, the per-filetype efm formatter / linter default to
-- `false` (the catalog still OFFERS black / isort / mypy / … for users who prefer efm-based tooling
-- — set `lsp = "basedpyright"` to drop ruff and let an efm formatter own the buffer). The whole
-- toolchain is VENV-AWARE (providers.python.venv): the interpreter, the LSP's import resolution, the
-- debugger and the test runner all use the project's virtual environment.
--
---@module "lvim-lang.providers.python"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.providers.python.toolchain")
local core_toolchain = require("lvim-lang.core.toolchain")
local requirements = require("lvim-lang.core.requirements")

--- Turn OFF an LSP client capability once (per-client, so it covers every buffer of that client).
---@param client table  the LSP client (server_capabilities toggled in place)
---@param cap string    server_capabilities key
---@return nil
local function disable_cap(client, cap)
    if client.server_capabilities then
        client.server_capabilities[cap] = false
    end
end

---@type table
local DEFAULTS = {
    -- Explicit binary paths; each wins over every other resolution strategy.
    python_path = nil,
    basedpyright_path = nil,
    ruff_path = nil,
    python_lookup_cmd = nil, -- shell command whose first line is the interpreter path
    -- Version manager for the interpreter: "mise" | "asdf" | "pyenv" | false | function(root).
    -- Honours a project's pin (.python-version / .tool-versions). Default: mise → asdf → pyenv → PATH.
    version_manager = nil,

    -- LSP server catalog. The default is a LIST — basedpyright (types) AND ruff (lint + format).
    -- Add / remove keys, or set `lsp.server = "basedpyright"` to run a single server.
    lsp = {
        servers = {
            basedpyright = {
                mason = "basedpyright",
                bin = "basedpyright-langserver",
                filetypes = { "python" },
                role = "types", -- completion / hover / definition / rename / inlay hints
                -- ruff owns formatting; basedpyright must not also format the buffer.
                on_attach = function(client, _bufnr)
                    disable_cap(client, "documentFormattingProvider")
                    disable_cap(client, "documentRangeFormattingProvider")
                end,
                settings = {
                    basedpyright = {
                        analysis = {
                            typeCheckingMode = "standard", -- "off"|"basic"|"standard"|"strict"|"all"
                            diagnosticMode = "openFilesOnly", -- or "workspace"
                            autoImportCompletions = true,
                            autoSearchPaths = true,
                            useLibraryCodeForTypes = true,
                            inlayHints = {
                                variableTypes = true,
                                callArgumentNames = true,
                                functionReturnTypes = true,
                                genericTypes = false,
                            },
                        },
                    },
                    -- `python.pythonPath` is injected per root by the server module (the resolved venv).
                    python = {},
                },
            },
            ruff = {
                mason = "ruff",
                bin = "ruff",
                filetypes = { "python" },
                role = "diagnostics", -- lint diagnostics + format + organize imports
                -- basedpyright owns hover; ruff's (rule docs) would otherwise double up.
                on_attach = function(client, _bufnr)
                    disable_cap(client, "hoverProvider")
                end,
                -- ruff server settings live under init_options.settings (set in servers/ruff.lua).
                init_options = {
                    settings = {
                        lineLength = 88,
                        lint = { enable = true },
                        format = { preview = false },
                        organizeImports = true,
                    },
                },
            },
        },
        default = { "basedpyright", "ruff" }, -- multi-LSP by default
    },

    -- Per-filetype catalog. ruff-the-LSP formats + lints by default, so the efm formatter / linter
    -- are `false`; the catalog still offers black / isort / autopep8 / yapf (formatters) and mypy /
    -- flake8 / pylint / pyflakes (linters) for users who prefer efm-based tooling.
    ft = {
        python = {
            formatters = {
                ruff = {
                    mason = "ruff",
                    efm = { formatCommand = "ruff format --stdin-filename ${INPUT} -", formatStdin = true },
                },
                black = { mason = "black", efm = { formatCommand = "black --quiet -", formatStdin = true } },
                isort = { mason = "isort", efm = { formatCommand = "isort --quiet -", formatStdin = true } },
                autopep8 = { mason = "autopep8", efm = { formatCommand = "autopep8 -", formatStdin = true } },
                yapf = { mason = "yapf", efm = { formatCommand = "yapf", formatStdin = true } },
            },
            linters = {
                ruff = {
                    mason = "ruff",
                    efm = {
                        lintCommand = "ruff check --output-format concise --stdin-filename ${INPUT} -",
                        lintStdin = true,
                        lintFormats = { "%f:%l:%c: %m" },
                    },
                },
                mypy = {
                    mason = "mypy",
                    efm = {
                        lintCommand = "mypy --show-column-numbers --hide-error-codes --no-error-summary --no-color-output",
                        lintStdin = false,
                        lintFormats = { "%f:%l:%c: %t%*[^:]: %m", "%f:%l: %t%*[^:]: %m" },
                        rootMarkers = { "pyproject.toml", "setup.cfg", "mypy.ini", ".mypy.ini" },
                    },
                },
                flake8 = {
                    mason = "flake8",
                    efm = {
                        lintCommand = "flake8 --stdin-display-name ${INPUT} -",
                        lintStdin = true,
                        lintFormats = { "%f:%l:%c: %m" },
                    },
                },
                pylint = {
                    mason = "pylint",
                    efm = {
                        lintCommand = "pylint --from-stdin ${INPUT} --output-format text --msg-template {path}:{line}:{column}:{C}:{msg} --score no",
                        lintStdin = true,
                        lintFormats = { "%f:%l:%c:%t:%m" },
                    },
                },
                pyflakes = {
                    mason = "pyflakes",
                    efm = { lintCommand = "pyflakes", lintStdin = false, lintFormats = { "%f:%l:%c %m", "%f:%l: %m" } },
                },
            },
            debuggers = {
                debugpy = { mason = "debugpy" },
            },
            defaults = { formatter = false, linter = false, debugger = "debugpy" },
        },
    },

    -- Codegen: `:LvimLang stub <import>` runs basedpyright `--createstub` (type-stub generation).
    -- On-demand — basedpyright's CLI ships with the LSP package, resolved through the toolchain.
    codegen = {},

    -- Dependency manager preference. `auto` detects it from the project (pyproject `[tool.poetry]` /
    -- `[tool.uv]`, `uv.lock`, `Pipfile`, else pip); pin it to "pip"|"poetry"|"uv"|"pipenv" to force one.
    dependency_manager = "auto",

    -- Statusline / picker icons (Nerd Font, all configurable).
    icons = {
        statusline = "󰌠", -- the Python marker in the statusline segment
        venv = "󰌠", -- interpreter / venv picker row
        test = "󰙨",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗", -- dependency row
    },
}

--- Health section for :checkhealth lvim-lang: the resolved interpreter (+ its environment), the
--- language servers and the debugger module, for the current working directory.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."
    local venv = require("lvim-lang.providers.python.venv")

    local py = core_toolchain.resolve("python", "python", root)
    if py then
        local ver = core_toolchain.version("python", "python", root)
        local dir = venv.dir(py)
        h.ok(
            ("python: %s%s%s"):format(py, ver and ("  (" .. ver .. ")") or "", dir and ("  [env " .. dir .. "]") or "")
        )
    else
        h.warn("python not found — install Python, create a .venv, or set providers.python.python_path")
    end

    for _, tool in ipairs({ "basedpyright", "ruff" }) do
        local path = core_toolchain.resolve("python", tool, root)
        if path then
            h.ok(("%s: %s"):format(tool, path))
        else
            h.info(("%s not found — installed on demand from the mason registry"):format(tool))
        end
    end

    -- debugpy is a python MODULE (run as `python -m debugpy`), not a standalone binary.
    if py then
        local out = vim.system({ py, "-c", "import debugpy" }, { cwd = root }):wait()
        if out.code == 0 then
            h.ok("debugpy: importable in the resolved interpreter")
        else
            h.info("debugpy not importable in the interpreter — installed on demand from the mason registry")
        end
    end
end

--- Statusline segment for a root: the Python marker + the environment name + the active run config.
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.python and config.providers.python.icons) or {}
    local parts = { ic.statusline or "" }
    local py = core_toolchain.resolve("python", "python", root)
    local dir = py and require("lvim-lang.providers.python.venv").dir(py)
    if dir then
        parts[#parts + 1] = vim.fs.basename(dir)
    end
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
    name = "python",
    filetypes = { "python" },
    root_patterns = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", "Pipfile", ".git" },
    statusline = statusline,
    toolchain = toolchain,
    commands = require("lvim-lang.providers.python.commands"),
    -- lvim-tasks templates (arg-less dependency subcommands) — also via :LvimLang deps.
    tasks = require("lvim-lang.providers.python.deps").templates,
    --- Surfaced at activation + in :checkhealth: a Python interpreter must be resolvable (server + debug).
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
        return {
            requirements.tool_present(
                "python",
                "python",
                "Python interpreter",
                "Select a project venv or install Python and put it on PATH (or set providers.python.python_path); "
                    .. "the language server and debugger need it.",
                root
            ),
        }
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
