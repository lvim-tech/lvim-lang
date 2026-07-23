# C / C++ provider

The C/C++ provider owns C-family tooling through `lvim-lang`: **clangd** (LSP — completion, hover,
navigation, inlay hints, native **clang-format** formatting and inline **clang-tidy** diagnostics),
build / run / test / configure through **lvim-tasks** (auto-detecting CMake / Make / a single file),
`compile_commands.json` generation, and **CodeLLDB** / **cpptools** debugging through **lvim-dap**.
Everything is resolved per project and lazy — nothing is wired until the first C/C++ buffer is opened.

Filetypes: `c`, `cpp`, `objc`, `objcpp`. Project root: `compile_commands.json` → `CMakeLists.txt` →
`Makefile` → `.clangd` → `.git`.

## Toolchain

Resolved per project root (nothing is installed here — see the install popup below). C/C++ has **no
version manager** (system compilers) and no universal package manager (conan / vcpkg are out of scope):

- **`clangd`** / **`clang-format`** / **`clang-tidy`** — an explicit path → the **mason** bin dir →
  `PATH`.
- **`cmake`** / **`make`** / **`cc`** / **`c++`** — an explicit path → `PATH` (system tools).

## Auto-install (the file-open popup)

Opening a C/C++ file offers the **active** tools it needs but lacks, through the unified
`lvim-installer` popup: the chosen **LSP server** (clangd), the chosen **debugger** (codelldb), and a
**formatter** / **linter** only if you select one (clangd formats + lints natively, so the defaults are
`false`). All are mason-registry packages installed by `lvim-pkg`'s own handlers — no `mason.nvim`.

## LSP server catalog

clangd is the single server for the whole C-family. It is configured through **command-line flags**
(not workspace settings): `--background-index --clang-tidy --header-insertion=iwyu
--completion-style=detailed --function-arg-placeholders`. When a formatter is active for a filetype,
clangd's own formatting is switched off automatically so the two don't both format.

| Server | Role | Filetypes |
| --- | --- | --- |
| `clangd` (default) | types / hover / definition / rename / inlay hints / format / clang-tidy | c, cpp, objc, objcpp |

## Per-filetype catalog

Each filetype shares the same catalog; you pick a default (or `false` for none). Only the chosen tools
are installed / wired. Formatting and linting are done by **clangd** natively (clang-format +
`--clang-tidy`), so the default formatter and linter are `false`; the catalog still offers clang-format
(efm formatter) and clang-tidy (efm linter).

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `c` / `cpp` / `objc` / `objcpp` | clang-format | clang-tidy | codelldb, cpptools | formatter=false, linter=false, debugger=codelldb |

## Build systems (auto-detected)

`:LvimLang build` / `run` / `test` detect the project shape at the root (first match wins):

| Detected | build | run | test |
| --- | --- | --- | --- |
| `CMakeLists.txt` | `cmake --build build` (configures first if needed) | run the built binary (prompt / run config) | `ctest --output-on-failure` |
| `Makefile` | `make` | run the built binary (prompt / run config) | `make test` |
| single file | compile with `cc` / `c++` into the cache | compile & run the produced binary | — |

## Commands

`:LvimLang <sub> [args]` in a C/C++ buffer:

| Command | Description |
| --- | --- |
| `:LvimLang build [args]` | build the project (cmake build / make / compile the file) |
| `:LvimLang run [args]` | run the built binary (applies the active run config) |
| `:LvimLang test [args]` | run tests (`ctest` / `make test`) |
| `:LvimLang test-func` | run the GoogleTest / Catch2 test under the cursor (`ctest -R`) |
| `:LvimLang configure [args]` | `cmake` configure into `build/` (exports `compile_commands.json`) |
| `:LvimLang compile-commands` | generate `compile_commands.json` (cmake export / `bear -- make`) |
| `:LvimLang debug` | start / continue a CodeLLDB / cpptools session |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

`:LvimLang test-func` maps the enclosing **GoogleTest** (`TEST` / `TEST_F` / `TEST_P` → `Suite.Name`) or
**Catch2** (`TEST_CASE` → the case string, `SCENARIO` → `Scenario: <name>`) test to the name CTest
registers and runs `ctest -R "^<name>$"` — works whenever the project registers its tests with CTest
(`gtest_discover_tests` / `catch_discover_tests`).

## Run configurations

Named configs in `.lvim/lang/run.lua` (a pure-data file). `:LvimLang config` picks the active one
(remembered per project); `:LvimLang run` applies its program / args / env.

```lua
return {
    {
        name = "server",
        program = "build/server", -- the built binary (relative to the root, or absolute)
        args = { "--verbose" }, -- program arguments
        env = { PORT = "8080" }, -- process environment
        cwd = nil, -- working directory (default: the project root)
    },
    { name = "app", program = "build/app" },
}
```

## Debugging

Two adapters are offered (the catalog default is **codelldb**): **CodeLLDB** (`codelldb --port ${port}`,
the LLVM debugger) and **cpptools** (`OpenDebugAD7`, the classic MI/GDB bridge). Launch configs prompt
for the executable (defaulting under `build/`); an attach config attaches to a running process. Build
the target first (`:LvimLang build`).

## Configuration

The complete default `providers.cpp` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        cpp = {
            -- Toolchain (explicit paths win over resolution). No version manager (system compilers).
            clangd_path = nil,
            clang_format_path = nil,
            clang_tidy_path = nil,
            cmake_path = nil,
            make_path = nil,
            cc_path = nil, -- the C compiler (default: `cc` on PATH)
            cxx_path = nil, -- the C++ compiler (default: `c++` on PATH)
            ctest_path = nil, -- the test driver (default: `ctest` on PATH)
            codelldb_path = nil,
            cpptools_path = nil, -- the cpptools debug adapter (OpenDebugAD7)

            -- The CMake build directory (relative to the project root).
            build_dir = "build",

            -- LSP server catalog + selection. clangd is configured via command-line FLAGS.
            lsp = {
                servers = {
                    clangd = {
                        mason = "clangd",
                        filetypes = { "c", "cpp", "objc", "objcpp" },
                        role = "types",
                        flags = {
                            "--background-index",
                            "--clang-tidy",
                            "--header-insertion=iwyu",
                            "--completion-style=detailed",
                            "--function-arg-placeholders",
                        },
                        init_options = {},
                        settings = {},
                    },
                },
                default = "clangd",
            },

            -- Per-filetype formatter / linter / debugger catalog + selection. Every C-family filetype
            -- (c / cpp / objc / objcpp) shares this catalog; the defaults are false for formatter +
            -- linter because clangd does both natively.
            ft = {
                -- shown for `cpp`; `c`, `objc`, `objcpp` are identical
                cpp = {
                    formatters = {
                        ["clang-format"] = {
                            mason = "clang-format",
                            efm = { formatCommand = "clang-format --assume-filename=${INPUT}", formatStdin = true },
                        },
                    },
                    linters = {
                        ["clang-tidy"] = {
                            mason = "clang-tidy",
                            efm = {
                                lintCommand = "clang-tidy ${INPUT} --quiet",
                                lintStdin = false,
                                lintFormats = {
                                    "%f:%l:%c: %trror: %m",
                                    "%f:%l:%c: %tarning: %m",
                                    "%f:%l:%c: %tote: %m",
                                },
                                rootMarkers = { "compile_commands.json", ".clang-tidy" },
                            },
                        },
                    },
                    debuggers = {
                        codelldb = { mason = "codelldb" },
                        cpptools = { mason = "cpptools", bin = "OpenDebugAD7" },
                    },
                    -- Only the chosen tools install / wire (false = none). clangd formats + lints natively.
                    defaults = { formatter = false, linter = false, debugger = "codelldb" },
                },
            },

            -- Statusline / picker icons (Nerd Font).
            icons = {
                statusline = "󰙲",
                test = "󰙨",
                build = "󰜫",
                run = "󰐊",
                debug = "󰃤",
                configure = "󱁤",
            },
        },
    },
})
```

## Available C/C++ packages (mason registry)

Filter `languages = C / C++`. In the catalog you pick from these; more exist in the registry and can be
added.

| Category | In the catalog | Also in the registry |
| --- | --- | --- |
| LSP | clangd | ccls |
| Formatter | clang-format | uncrustify, astyle |
| Linter | clang-tidy | cpplint, cppcheck |
| DAP | codelldb, cpptools (OpenDebugAD7) | — |

## Tests (`:LvimTest`) and builds (`:LvimBuild`)

The **lvim-test** `cpp` adapter discovers GoogleTest / Catch2 tests and runs them per-test through
CTest (see the adapter for its granularity and limitations). **lvim-build** already covers C/C++ through
its `cmake`, `make`, and single-file `c` / `cpp` recipes — no separate recipe is needed.
