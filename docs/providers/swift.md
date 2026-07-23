# Swift provider

The Swift provider owns Swift tooling through `lvim-lang`: **sourcekit-lsp** (LSP, shipped with the
Swift toolchain), `swift build` / `run` / `test` / `clean` and **swiftformat** through **lvim-tasks**,
XCTest test running (whole suite / target / method under the cursor), SwiftPM dependency commands, and
**lldb-dap** debugging through **lvim-dap**. Everything is resolved per project and lazy — nothing is
wired until the first Swift buffer is opened.

Filetypes: `swift`. Project root: `Package.swift` → `.git`.

## Toolchain

Resolved per project root (explicit path wins over everything):

- **`swift`** — explicit `swift_path` → `swift_lookup_cmd` (the seam for swiftly, which has no `which`
  verb) → version manager (**mise**, then **asdf**) → PATH. Swift is the user's **own** toolchain (not
  lvim-pkg-installed).
- **`sourcekit-lsp`** — **ships with the Swift toolchain** (no mason package): explicit
  `sourcekit_lsp_path` → beside the resolved `swift` in its bin dir → PATH.
- **`swiftformat`** — explicit → the mason bin → PATH.
- **`lldb-dap`** / **`codelldb`** — explicit → the mason bin → PATH.

A missing `swift` is surfaced at activation and in `:checkhealth` with an install hint.

## Auto-install (the file-open popup)

Opening a Swift file offers the **active** tools it lacks through the unified `lvim-installer` popup:
the default formatter (swiftformat) and the default debugger (lldb-dap), plus any chosen linter
(swiftlint). sourcekit-lsp is **not** offered — it comes with the Swift toolchain.

## LSP server catalog

sourcekit-lsp is the only server; it ships with the toolchain (no mason package — its presence is the
toolchain's / health's concern).

| Server | Role | Filetypes |
| --- | --- | --- |
| `sourcekit-lsp` (default) | types / hover / definition / rename / format / diagnostics | swift |

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `swift` | swiftformat (efm) | swiftlint (efm) | lldb-dap, codelldb | formatter=swiftformat, linter=false, debugger=lldb-dap |

swiftformat is the default formatter (over efm); sourcekit-lsp's own formatting is disabled on attach so
the two never both format. swiftlint is opt-in (`ft.swift.linter = "swiftlint"`) — sourcekit-lsp
provides diagnostics by default.

## Commands

`:LvimLang <sub> [args]` in a Swift buffer:

| Command | Description |
| --- | --- |
| `:LvimLang build [args]` | `swift build` |
| `:LvimLang run [args]` | `swift run` (+ the active run config) |
| `:LvimLang test [args]` | `swift test` — the whole suite |
| `:LvimLang test-func` | run the XCTest method under the cursor (`swift test --filter Class/method`) |
| `:LvimLang clean [args]` | `swift package clean` |
| `:LvimLang fmt [args]` | `swiftformat` — format the package |
| `:LvimLang update` | `swift package update` |
| `:LvimLang deps <resolve\|update\|describe\|show-dependencies>` | SwiftPM dependency commands |
| `:LvimLang debug` | start / continue an lldb-dap session |
| `:LvimLang debug-test` | debug the XCTest method under the cursor (builds the `.xctest` bundle, launches under lldb-dap) |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

## Debugging

Debugging uses **lldb-dap** (codelldb as an alternative). `:LvimLang debug` launches / continues a
session on the built executable; `:LvimLang debug-test` builds the test bundle
(`swift build --build-tests`) then launches the `.xctest` for the method under the cursor under
lldb-dap — the build step is why per-test debugging lives here rather than in a synchronous
`:LvimTest` debug config.

## Run configurations

Named configs in `.lvim/lang/run.lua`. `:LvimLang config` picks the active one; `:LvimLang run` applies
its args / env.

```lua
return {
    {
        name = "app",
        args = { "--verbose" }, -- program arguments
        env = { LOG = "debug" },
    },
    { name = "default" },
}
```

## Configuration

The complete default `providers.swift` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        swift = {
            -- Toolchain (explicit paths win over resolution).
            swift_path = nil,
            sourcekit_lsp_path = nil,
            swiftformat_path = nil,
            lldb_dap_path = nil,
            codelldb_path = nil,
            swift_lookup_cmd = nil, -- shell command whose first non-empty line is the `swift` path (swiftly &c.)
            version_manager = nil, -- "mise"|"asdf"|false|function(root); default: mise→asdf→PATH

            -- LSP server catalog + selection. sourcekit-lsp ships with the toolchain (no `mason`).
            lsp = {
                servers = {
                    ["sourcekit-lsp"] = {
                        filetypes = { "swift" },
                        role = "types",
                        settings = {},
                        init_options = {},
                    },
                },
                default = "sourcekit-lsp",
            },

            -- Per-filetype formatter / linter / debugger catalog + selection.
            ft = {
                swift = {
                    formatters = {
                        swiftformat = {
                            mason = "swiftformat",
                            efm = { formatCommand = "swiftformat --quiet", formatStdin = true },
                        },
                    },
                    linters = {
                        swiftlint = {
                            mason = "swiftlint",
                            efm = {
                                lintCommand = "swiftlint lint --quiet ${INPUT}",
                                lintStdin = false,
                                lintFormats = { "%f:%l:%c: %t%*[^:]: %m" },
                                rootMarkers = { ".swiftlint.yml", ".swiftlint.yaml" },
                            },
                        },
                    },
                    debuggers = {
                        ["lldb-dap"] = { mason = "lldb-dap" },
                        codelldb = { mason = "codelldb" },
                    },
                    defaults = { formatter = "swiftformat", linter = false, debugger = "lldb-dap" },
                },
            },

            -- Nerd Font icons (statusline / picker rows).
            icons = {
                statusline = "", -- nf-seti-swift (U+E755)
                test = "󰙨",
                build = "󰜫",
                run = "󰐊",
                debug = "󰃤",
                deps = "󰏗",
            },
        },
    },
})
```
