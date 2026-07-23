# Scala provider

The Scala provider owns Scala tooling through `lvim-lang`: **metals** (the Scala language server),
`scalafmt` formatting (opt-in, routed through **efm-langserver**), `sbt` / `mill` / `bloop` build /
run / test through **lvim-tasks**, suite-level test running (whole suite, the current buffer's suite),
dependency inspection, and **metals-driven** debugging through **lvim-dap**. Everything is resolved
per project and lazy — nothing is wired until the first Scala buffer is opened.

Filetypes: `scala`, `sbt`. Project root: `build.sbt` / `build.sc` → `.git`.

## metals owns the build server

metals is not just an LSP — it imports the project's build (sbt / mill / bloop), runs its own
**Bloop** build server over BSP, and drives compilation, diagnostics, code lenses **and** debugging
from it. lvim-lang therefore never hand-rolls a BSP client: it starts metals and lets metals own the
build server. Debugging goes through metals' own `debug-adapter-start` executeCommand (the canonical
metals debug seam). The `sbt` / `mill` / `bloop` invocations below are for fire-and-collect build /
run / test tasks in the lvim-tasks panel — independent of the editor's own compile.

## Toolchain

Resolved per project root (nothing is installed here — see the install popup below):

- **`sbt`** / **`mill`** — an explicit path (`sbt_path` / `mill_path`) → a lookup command → a
  **version manager** (`mise` / `asdf` / `sdkman`, honouring the project's pinned toolchain; `sbt` is
  a SDKMAN candidate, `mill` is not) → `PATH`.
- **`java`** — an explicit `java_path` → a `java_lookup_cmd` → a version manager → `PATH`.
- **`metals`** / **`scalafmt`** — an explicit path → the mason bin / `PATH`.
- **`bloop`** — an explicit `bloop_path` → `PATH` (the user's own coursier install).

metals is a JVM program (needs `java` 11+, 17 recommended) launched through the mason `metals`
wrapper. The Java-runtime requirement is surfaced in `:checkhealth lvim-lang` and as a one-time notice
when a Scala buffer opens, rather than letting metals crash with an opaque error.

## Build tool

Every runnable action detects the project's build tool at the root: `build.sbt` → **sbt**;
`build.sc` → **mill**; a `.bloop/` directory → **bloop** (sbt is checked first). The project
**wrapper** (`./sbt` / `./mill`) is preferred when present (it pins the exact tool version), else the
toolchain-resolved binary, else the system name.

The three tools are asymmetric: sbt runs a bare `run` / `runMain <main>`; mill addresses a **module**
(`<module>.run`), so a single-target run / test needs `mill_module`; bloop addresses a **project**
(`run <project>`), defaulting to the root basename (`bloop_project` to override). Whole-suite build /
test map cleanly on all three.

## Auto-install (the file-open popup)

Opening a Scala file offers the **active** tools it needs but lacks, through the unified
`lvim-installer` popup: the **LSP server** (metals), plus a **formatter** (scalafmt) if you select the
efm one. All are mason-registry packages installed by `lvim-pkg`'s own handlers — no `mason.nvim`.

## LSP server catalog

metals is the single Scala server; its settings live under `settings.metals` and its
`initializationOptions` under `init_options`. When a formatter is active for the buffer, metals' own
formatting is switched off automatically so the two don't both format.

| Server | Role | Filetypes |
| --- | --- | --- |
| `metals` (default) | types / hover / definition / rename / code lenses / format | scala, sbt |

## Per-filetype catalog

metals formats Scala natively (it shells out to scalafmt when a `.scalafmt.conf` is present), so the
efm **formatter** defaults to `false`. scalafmt is still offered — to use it via efm, set
`ft.scala.formatter = "scalafmt"`. There is no first-class standalone Scala linter (the compiler +
metals own diagnostics), and metals drives debugging itself — so no efm linter / DAP package.

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `scala` | scalafmt | — | — | formatter=false, linter=false, debugger=false |
| `sbt` | — | — | — | formatter=false, linter=false, debugger=false |

## Commands

`:LvimLang <sub> [args]` in a Scala buffer:

| Command | Description |
| --- | --- |
| `:LvimLang build [args]` | `sbt compile` / `mill __.compile` / `bloop compile <project>` |
| `:LvimLang run [args]` | `sbt run` / `mill <module>.run` / `bloop run <project>`; applies the active run config |
| `:LvimLang test [args]` | `sbt test` / `mill __.test` / `bloop test <project>` — the whole suite |
| `:LvimLang test-file` | run every test in the current buffer's suite (`testOnly pkg.Suite`) |
| `:LvimLang test-func` | run the enclosing suite (Scala isolates per-suite — see below) |
| `:LvimLang deps <tree\|refresh\|install>` | dependency graph / re-resolve / publishLocal |
| `:LvimLang debug` | start / continue a metals debug session |
| `:LvimLang debug-test` | debug the current buffer's test suite(s) via metals |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

Adding / removing a dependency is done by editing `build.sbt` / `build.sc` directly — there is no
clean, non-destructive CLI verb for it, so `deps` exposes only the safe read/resolve operations (sbt
has `dependencyTree` / `update` / `publishLocal`; mill's need `mill_module`; bloop has no dep verbs).

### Test granularity (per-suite)

Scala test frameworks (ScalaTest / munit / utest / specs2) express individual tests as a DSL, not as
named methods, and the single-test selector differs per framework. `test-func` therefore runs the
enclosing **suite** — the finest granularity that works everywhere — with a one-time notice.

## Debugging

Debugging is driven by metals: it starts a Debug Adapter over its Bloop BSP connection on demand
(`debug-adapter-start`) and returns the server URI, which lvim-dap connects to. The base
configurations are metals `runType`s (metals resolves the concrete target from the current file):

| Configuration | runType |
| --- | --- |
| Run or test current file | `runOrTestFile` |
| Test current file | `testFile` |
| Test build target | `testTarget` |

`debug-test` starts a `testFile` session for the current buffer.

## Run configurations

Named configs in `.lvim/lang/run.lua` (a pure-data file). `:LvimLang config` picks the active one
(remembered per project); `:LvimLang run` applies its main class / args / env.

```lua
return {
    {
        name = "app",
        main_class = "com.example.Main", -- sbt runMain / mill <module>.runMain / bloop -m
        args = { "--port", "8080" }, -- program arguments
        env = { SCALA_ENV = "dev" }, -- process environment
    },
}
```

## Configuration

The complete default `providers.scala` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        scala = {
            -- Toolchain (explicit paths win over resolution).
            sbt_path = nil,
            mill_path = nil,
            bloop_path = nil,
            java_path = nil,
            metals_path = nil,
            scalafmt_path = nil,
            sbt_lookup_cmd = nil, -- shell command whose first line is the `sbt` path
            mill_lookup_cmd = nil,
            java_lookup_cmd = nil,
            version_manager = nil, -- "mise"|"asdf"|"sdkman"|false|function(root,bin); default: mise→asdf→sdkman→PATH

            -- mill needs a module to run / test a single target; bloop addresses a project.
            mill_module = nil, -- e.g. "app" (nil → whole-suite targets only)
            bloop_project = nil, -- nil → the project-root basename

            -- How long to wait for metals' DAP server before lvim-dap connects.
            debug_attach_delay_ms = 500,

            -- LSP server catalog + selection.
            lsp = {
                servers = {
                    metals = {
                        mason = "metals",
                        filetypes = { "scala", "sbt" },
                        role = "types",
                        settings = {
                            metals = {
                                showImplicitArguments = true,
                                showImplicitConversionsAndClasses = true,
                                showInferredType = true,
                                superMethodLensesEnabled = true,
                                enableSemanticHighlighting = false,
                                excludedPackages = {},
                            },
                        },
                        init_options = {
                            statusBarProvider = "off",
                            isHttpEnabled = true,
                            compilerOptions = { snippetAutoIndent = false },
                        },
                    },
                },
                default = "metals", -- string | string[] (a list attaches several LSP clients)
            },

            -- Per-filetype formatter / linter / debugger catalog + selection.
            ft = {
                scala = {
                    formatters = {
                        scalafmt = {
                            mason = "scalafmt",
                            efm = { formatCommand = "scalafmt --stdin --non-interactive", formatStdin = true },
                        },
                    },
                    linters = {},
                    debuggers = {},
                    -- metals formats + diagnoses natively; scalafmt is opt-in (set formatter = "scalafmt").
                    defaults = { formatter = false, linter = false, debugger = false },
                },
                sbt = {
                    formatters = {},
                    linters = {},
                    debuggers = {},
                    defaults = { formatter = false, linter = false, debugger = false },
                },
            },

            -- Statusline / picker icons (Nerd Font).
            icons = {
                statusline = "",
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

## Available Scala packages (mason registry)

Filter `languages = Scala`. In the catalog you pick from these; more exist in the registry and can be
added to the catalog.

| Category | In the catalog | Also in the registry |
| --- | --- | --- |
| LSP | metals | — |
| Formatter | scalafmt | — |
| Linter | — (metals / compiler own diagnostics) | — |
| DAP | — (metals drives debugging over BSP) | — |
