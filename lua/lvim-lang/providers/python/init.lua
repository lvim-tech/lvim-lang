-- lvim-lang.providers.python: the Python provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes, the MULTI-LSP catalog (basedpyright for types AND ruff for lint/format, both attaching
-- by default, coordinated via per-server on_attach), the per-filetype tool catalog (ruff/black/isort/…
-- formatters, ruff/mypy/flake8/… linters, debugpy), the python toolchain, the requirement, health and
-- statusline. This module then EXTENDS the returned spec with Python's VENV-AWARENESS — the interpreter
-- and every tool use the project's virtual environment (providers.python.venv):
--   * the interpreter resolves config → persisted pick → auto-detected env (.venv/poetry/pipenv/conda/…)
--     → mise/asdf/pyenv → python3/python;
--   * basedpyright / ruff / basedpyright-cli resolve from that env FIRST (a `pip install`ed tool wins),
--     then mason, then PATH;
--   * the pip/poetry/uv + pytest/unittest command surface (providers.python.commands / .deps / .venv).
--
-- ruff-the-LSP owns formatting + linting, so the efm formatter/linter default off. basedpyright / ruff
-- keep their bespoke server-config modules (a real file wins over the generic shim).
--
---@module "lvim-lang.providers.python"

local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")
local detect = require("lvim-lang.core.detect")
local core_toolchain = require("lvim-lang.core.toolchain")
local venv = require("lvim-lang.providers.python.venv")

--- Turn OFF an LSP client capability once (per-client, so it covers every buffer of that client).
---@param client table  the LSP client (server_capabilities toggled in place)
---@param cap string    server_capabilities key
---@return nil
local function disable_cap(client, cap)
    if client.server_capabilities then
        client.server_capabilities[cap] = false
    end
end

---@type LvimLangSpecData
local DATA = {
    name = "python",
    filetypes = { "python" },
    root_patterns = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", "Pipfile", ".git" },

    -- The interpreter is required; its resolution is VENV-AWARE and overridden in the extend below.
    runtime = {
        bin = "python",
        key = "python",
        lookup_key = "python_lookup_cmd",
        managers = { "mise", "asdf", "pyenv" },
        require = true,
        label = "Python interpreter",
        hint = "Select a project venv or install Python and put it on PATH (or set providers.python.bin_paths.python); "
            .. "the language server and debugger need it.",
    },

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

    icons = {
        statusline = "󰌠", -- the Python marker in the statusline segment
        venv = "󰌠", -- interpreter / venv picker row
        test = "󰙨",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗", -- dependency row
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND: venv-aware toolchain resolution ─────────────────────────────────────────────────────────

--- A tool `bin` inside the resolved interpreter's environment (`<env>/bin/<bin>` or `<env>/Scripts/<bin>`),
--- if executable — so a project that `pip install`ed the tool into its venv is preferred over mason.
---@param bin string
---@return fun(root: string): string|nil
local function in_venv(bin)
    return function(root)
        local py = core_toolchain.resolve("python", "python", root)
        local dir = py and venv.dir(py)
        if not dir then
            return nil
        end
        for _, sub in ipairs({ "bin", "Scripts" }) do
            local p = vim.fs.joinpath(dir, sub, bin)
            if vim.fn.executable(p) == 1 then
                return p
            end
        end
        return nil
    end
end

local tc = spec.toolchain.tools
-- The interpreter: config → persisted pick → auto-detected env → version manager → python3 / python.
tc.python = {
    { kind = "path", value = detect.explicit("python", "python") },
    { kind = "path", value = venv.selected },
    {
        kind = "path",
        value = function(root)
            return (select(1, venv.detect(root)))
        end,
    },
    {
        kind = "path",
        value = detect.via_version_manager("python", "python", { managers = { "mise", "asdf", "pyenv" } }),
    },
    { kind = "which", value = "python3" },
    { kind = "which", value = "python" },
}
-- basedpyright / ruff resolve from the project env before mason (a pip-installed tool wins).
table.insert(tc.basedpyright, 2, { kind = "path", value = in_venv("basedpyright-langserver") })
table.insert(tc.ruff, 2, { kind = "path", value = in_venv("ruff") })
-- basedpyright's CLI (used by `:LvimLang stub --createstub`): env → mason → PATH.
tc["basedpyright-cli"] = {
    { kind = "path", value = in_venv("basedpyright") },
    { kind = "path", value = detect.in_mason("basedpyright") },
    { kind = "which", value = "basedpyright" },
}

-- Dependency manager preference ("auto" detects poetry/uv/pipenv/pip); codegen is on-demand (tsc-less).
defaults.dependency_manager = "auto"
defaults.codegen = {}

spec.commands = require("lvim-lang.providers.python.commands")
spec.tasks = require("lvim-lang.providers.python.deps").templates

registry.register(spec, defaults)

return spec
