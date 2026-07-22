# Python provider

The Python provider owns Python tooling through `lvim-lang`: a **multi-LSP** setup —
**basedpyright** (types / hover / completion / inlay hints) **and** **ruff** (lint diagnostics +
format + organize imports) attaching to the same buffer — plus `python` run / test / coverage
through **lvim-tasks**, **pytest** / **unittest** test running (whole suite, current file, the test
under the cursor), a coverage gutter overlay, `pip` / `poetry` / `uv` / `pipenv` dependency
management (auto-detected), type-stub generation (**basedpyright `--createstub`**), and **debugpy**
debugging through **lvim-dap**. Everything is **venv-aware** and resolved per project — the LSP's
import resolution, the debugger and the test runner all use the project's virtual environment —
lazy: nothing is wired until the first Python buffer is opened.

Filetypes: `python`. Project root: `pyproject.toml` → `setup.py` → `setup.cfg` → `requirements.txt`
→ `Pipfile` → `.git`.

## Toolchain (venv-aware)

The `python` interpreter is the crux — everything runs under it. Resolved per project root:

- **`python`** — an explicit `python_path` → the **persisted interpreter pick** (`:LvimLang venv`)
  → an **auto-detected environment** (`$VIRTUAL_ENV` → in-tree `.venv` / `venv` → `poetry` →
  `pipenv` → `$CONDA_PREFIX`) → a **version manager** (`mise` / `asdf` / `pyenv`, honouring the
  project's pin) → `python3` / `python` on `PATH`.
- **`basedpyright`** / **`ruff`** — an explicit path → the **project environment** (`<venv>/bin`, so
  a `pip install`ed tool wins) → the mason bin → `PATH`.

`:LvimLang venv` opens a picker of the discovered interpreters (the choice is remembered per
project); `:LvimLang venv create [name]` creates a `.venv` (`python -m venv`) and selects it.

## Auto-install (the file-open popup)

Opening a Python file offers the **active** tools it needs but lacks, through the unified
`lvim-installer` popup: the chosen **LSP servers** (basedpyright + ruff), the chosen **debugger**
(debugpy), and a **formatter** / **linter** if you select an efm one. All are mason-registry
packages installed by `lvim-pkg`'s own handlers — no `mason.nvim`.

## LSP server catalog

The default is a **list** — Python is the first provider whose default LSP is multi-server. Each
owns what it is best at, and their capabilities are coordinated so they never double up: basedpyright
yields formatting to ruff (its formatting is switched off), ruff yields hover to basedpyright. Set
`lsp.server = "basedpyright"` to run a single server.

| Server | Role | Filetypes |
| --- | --- | --- |
| `basedpyright` (default) | types / hover / completion / definition / rename / inlay hints | python |
| `ruff` (default) | lint diagnostics + format + organize imports | python |

basedpyright is pointed at the resolved interpreter (`python.pythonPath`) so imports resolve against
the project's environment.

## Per-filetype catalog

`ruff`-the-LSP owns formatting and linting by default, so the efm **formatter** and **linter**
default to `false`. The catalog still offers efm tools for users who prefer them — to use, say,
`black` + `mypy` via efm, set `ft.python.formatter = "black"`, `ft.python.linter = "mypy"` and drop
ruff from the LSP list (`lsp.server = "basedpyright"`) so the two don't both format.

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `python` | ruff, black, isort, autopep8, yapf | ruff, mypy, flake8, pylint, pyflakes | debugpy | formatter=false, linter=false, debugger=debugpy |

## Commands

`:LvimLang <sub> [args]` in a Python buffer:

| Command | Description |
| --- | --- |
| `:LvimLang run [args]` | run the current file (or the active run config) under the venv interpreter |
| `:LvimLang run-module <module> [args]` | `python -m <module>` |
| `:LvimLang check [args]` | `python -m compileall` — a byte-compile sanity pass |
| `:LvimLang test [args]` | `pytest` — the whole suite |
| `:LvimLang test-file` | `pytest` the current file |
| `:LvimLang test-func` | run the `def test_*` under the cursor (pytest node id) |
| `:LvimLang unittest [target]` | `python -m unittest` (discover by default) |
| `:LvimLang coverage [clear]` | `coverage run -m pytest` + a green/red gutter overlay |
| `:LvimLang venv [create [name]]` | pick an interpreter, or create + select a virtual environment |
| `:LvimLang add <package…>` | add a dependency (auto-detected manager) |
| `:LvimLang remove <package…>` | remove a dependency |
| `:LvimLang update [package…]` | update dependencies |
| `:LvimLang deps <install\|update\|tree\|lock>` | dependency commands |
| `:LvimLang stub <import>` | generate `.pyi` type stubs (basedpyright `--createstub`) |
| `:LvimLang debug` | start / continue a debugpy session |
| `:LvimLang debug-test` | debug the pytest test under the cursor |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

### Dependency managers

The manager is detected from the project (unless pinned via `dependency_manager`): `pyproject.toml`
`[tool.poetry]` → **poetry**; `[tool.uv]` or `uv.lock` → **uv**; `Pipfile` → **pipenv**; else
**pip** (run as `python -m pip` under the venv). `add` / `remove` / `update` / `deps install` /
`deps lock` / `deps tree` map to each manager's own verbs.

## Run configurations

Named configs in `.lvim/lang/run.lua` (a pure-data file). `:LvimLang config` picks the active one
(remembered per project); `:LvimLang run` applies its entry point / args / env.

```lua
return {
    {
        name = "api",
        module = "uvicorn", -- `python -m uvicorn` (mutually exclusive with `script`)
        args = { "app:app", "--reload" }, -- program arguments
        env = { PYTHONUNBUFFERED = "1" }, -- process environment
    },
    {
        name = "script",
        script = "main.py", -- a file to run (`python main.py`)
        args = { "--verbose" },
    },
}
```

## Configuration

The complete default `providers.python` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        python = {
            -- Toolchain (explicit paths win over resolution).
            python_path = nil,
            basedpyright_path = nil,
            ruff_path = nil,
            python_lookup_cmd = nil, -- shell command whose first line is the interpreter path
            version_manager = nil, -- "mise"|"asdf"|"pyenv"|false|function(root); default: mise→asdf→pyenv→PATH

            -- LSP server catalog + selection (the default is a LIST — multi-LSP).
            lsp = {
                servers = {
                    basedpyright = {
                        mason = "basedpyright",
                        bin = "basedpyright-langserver",
                        filetypes = { "python" },
                        role = "types",
                        -- (basedpyright's formatting is switched off in its on_attach; ruff formats.)
                        settings = {
                            basedpyright = {
                                analysis = {
                                    typeCheckingMode = "standard", -- off|basic|standard|strict|all
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
                            python = {}, -- `python.pythonPath` is injected per root (the resolved venv)
                        },
                    },
                    ruff = {
                        mason = "ruff",
                        bin = "ruff",
                        filetypes = { "python" },
                        role = "diagnostics",
                        -- (ruff's hover is switched off in its on_attach; basedpyright hovers.)
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
                default = { "basedpyright", "ruff" }, -- string | string[] (a list attaches several clients)
            },

            -- Per-filetype formatter / linter / debugger catalog + selection.
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
                            efm = {
                                lintCommand = "pyflakes",
                                lintStdin = false,
                                lintFormats = { "%f:%l:%c %m", "%f:%l: %m" },
                            },
                        },
                    },
                    debuggers = {
                        debugpy = { mason = "debugpy" },
                    },
                    -- Only the chosen tools install / wire (false = none). ruff-the-LSP formats + lints.
                    defaults = { formatter = false, linter = false, debugger = "debugpy" },
                },
            },

            -- `:LvimLang stub <import>` uses basedpyright's bundled CLI — no separate install.
            codegen = {},

            -- Dependency manager: "auto" detects it; pin to "pip"|"poetry"|"uv"|"pipenv" to force one.
            dependency_manager = "auto",

            -- Statusline / picker icons (Nerd Font).
            icons = {
                statusline = "󰌠",
                venv = "󰌠",
                test = "󰙨",
                run = "󰐊",
                debug = "󰃤",
                deps = "󰏗",
            },
        },
    },
})
```

## Available Python packages (mason registry)

Filter `languages = Python`. In the catalog you pick from these; more exist in the registry and can
be added to the catalog.

| Category | In the catalog | Also in the registry |
| --- | --- | --- |
| LSP | basedpyright, ruff | pyright, pylsp, jedi-language-server, pyre |
| Formatter | ruff, black, isort, autopep8, yapf | blue, docformatter |
| Linter | ruff, mypy, flake8, pylint, pyflakes | pydocstyle, bandit, pycodestyle, semgrep |
| DAP | debugpy | — |
