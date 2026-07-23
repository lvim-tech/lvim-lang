# Clojure provider

The Clojure provider owns Clojure tooling through `lvim-lang`: **clojure-lsp** (LSP), **run / test**
through **lvim-tasks** via the project's build tool (the Clojure CLI, Leiningen or Boot), `clojure.test`
test running (whole suite / current namespace / `deftest` under the cursor), and **cljfmt** (format) +
**clj-kondo** (lint) through **efm**. Everything is resolved per project and lazy — nothing is wired
until the first Clojure buffer is opened.

Filetypes: `clojure`, `edn`. Project root: `deps.edn` → `project.clj` → `build.boot` →
`shadow-cljs.edn` → `.git`.

## Toolchain

Clojure is a JVM language: the Clojure CLI / Leiningen, every test run, and clojure-lsp's classpath
resolution all execute on **`java`**. Resolved per project root (explicit path wins over everything):

- **`clojure`** / **`clj`** / **`lein`** / **`boot`** — explicit path → `*_lookup_cmd` → version
  manager (**mise**, **asdf**; **SDKMAN** for `lein` / `java`, the candidates it ships) → PATH.
- **`java`** — the JVM everything runs on: explicit → `java_lookup_cmd` → version manager → PATH.
  Clojure / the JDK are the user's **own** toolchain (not lvim-pkg-installed).
- **`clojure-lsp`** / **`cljfmt`** / **`clj-kondo`** — explicit path → the mason bin → PATH.

`:checkhealth` and the activation notice surface a missing build tool, a missing **Java** runtime, and a
Java that is too old (Clojure needs Java 8+).

## Auto-install (the file-open popup)

Opening a Clojure file offers the **active** tools it lacks through the unified `lvim-installer` popup:
clojure-lsp (LSP), cljfmt (the default formatter) and clj-kondo (the default linter). Clojure / the JDK
are not offered — they are the user's toolchain. There is no standard Clojure debugger, so none is
offered.

## LSP server catalog

clojure-lsp is the single server. It is a native GraalVM binary launched directly (it needs no JVM to
run itself), but resolves a project's classpath by shelling out to the Clojure CLI / Leiningen, which do
need `java`.

| Server | Role | Filetypes |
| --- | --- | --- |
| `clojure-lsp` (default) | types / hover / definition / rename / format | clojure, edn |

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `clojure` | cljfmt (efm) | clj-kondo (efm) | — | formatter=cljfmt, linter=clj-kondo |
| `edn` | cljfmt (efm) | — | — | formatter=cljfmt |

cljfmt is the canonical Clojure formatter and clj-kondo the canonical linter (both via efm). `edn` is
data, so it gets cljfmt formatting but no linter. clj-kondo lints the live buffer over stdin but reads
the language + config from the real filename (`${INPUT}`), so a `.clj` / `.cljs` / `.cljc` / `deps.edn`
each get the right rules. clojure-lsp's own formatting is disabled on attach while an efm formatter is
active, so the two never both format.

## Commands

`:LvimLang <sub> [args]` in a Clojure buffer:

| Command | Description |
| --- | --- |
| `:LvimLang run [args]` | `clojure -M:run` / `lein run` / `boot run` (+ the active run config) |
| `:LvimLang test [args]` | `clojure -X:test` / `lein test` / `boot test` — the whole suite |
| `:LvimLang test-file` | run every test in the current namespace |
| `:LvimLang test-func` | run the `deftest` under the cursor |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

The Clojure CLI has no canonical run/test verb — projects wire **aliases** in `deps.edn` — so both are
configurable (`tasks.clj.run_alias` / `tasks.clj.test_alias`), and `tasks.clj.test_exec` selects the
`-X` exec runner (the Cognitect test-runner, which enables per-test / per-namespace filtering) vs a
`-M` main. Leiningen filters with `lein test :only <ns>/<test>`; the CLI exec runner with `:vars` /
`:nses`; a `-M` alias or Boot cannot filter, so `test-func` / `test-file` fall back to the whole suite
with a notice.

## Dependencies

Clojure dependencies are declared by editing `deps.edn` / `project.clj` — there is no clean,
non-destructive CLI verb to add or remove one — so no `deps` subcommand is offered.

## nREPL (planned)

An nREPL eval seam (`:LvimLang repl` / `eval` — connect to a running nREPL via `.nrepl-port` and eval
the form under the cursor) is not wired yet. It needs a bencode-over-TCP client (a different transport
from `lvim-lang.core.daemon`'s jobstart + newline-JSON framing), so it is deferred rather than shipped
as a stopgap.

## Run configurations

Named configs in `.lvim/lang/run.lua`. `:LvimLang config` picks the active one; `:LvimLang run` applies
its args / env. For the Clojure CLI, a `main_ns` maps to `clojure -M -m <ns>` and an `alias` to
`clojure -M:<alias>` (overriding the default run alias).

```lua
return {
    {
        name = "app",
        main_ns = "my.app.core", -- Clojure CLI: `-M -m my.app.core`
        args = { "--profile", "dev" }, -- program arguments
        env = { ENV = "dev" },
    },
    { name = "alias", alias = "dev" }, -- Clojure CLI: `-M:dev`
}
```

## Configuration

The complete default `providers.clojure` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        clojure = {
            -- Toolchain (explicit paths win over resolution).
            clojure_path = nil,
            clj_path = nil,
            lein_path = nil,
            boot_path = nil,
            java_path = nil,
            clojure_lsp_path = nil,
            cljfmt_path = nil,
            clj_kondo_path = nil,
            clojure_lookup_cmd = nil, -- shell command whose first line is the `clojure`/`clj` path
            lein_lookup_cmd = nil,
            boot_lookup_cmd = nil,
            java_lookup_cmd = nil,
            version_manager = nil, -- "mise"|"asdf"|"sdkman"|false|function(root, bin); default: mise→asdf→sdkman→PATH

            -- How run / test invoke the Clojure CLI (deps.edn projects have no canonical run/test verb).
            tasks = {
                clj = {
                    run_alias = "run", -- `clojure -M:run`
                    test_alias = "test", -- the `:test` alias for the test runner
                    test_exec = true, -- true → `clojure -X:test` (exec, filters); false → `clojure -M:test` (main)
                },
            },

            -- LSP server catalog + selection. clojure-lsp is a native GraalVM binary (no JVM itself).
            lsp = {
                servers = {
                    ["clojure-lsp"] = {
                        mason = "clojure-lsp",
                        filetypes = { "clojure", "edn" },
                        role = "types",
                        settings = {},
                    },
                },
                default = "clojure-lsp",
            },

            -- Per-filetype formatter / linter catalog + selection (no debugger — no standard Clojure DAP).
            ft = {
                clojure = {
                    formatters = {
                        cljfmt = {
                            mason = "cljfmt",
                            efm = { formatCommand = "cljfmt fix -", formatStdin = true },
                        },
                    },
                    linters = {
                        ["clj-kondo"] = {
                            mason = "clj-kondo",
                            efm = {
                                lintCommand = "clj-kondo --lint - --filename ${INPUT}",
                                lintStdin = true,
                                lintFormats = { "%f:%l:%c: %trror: %m", "%f:%l:%c: %tarning: %m" },
                            },
                        },
                    },
                    debuggers = {},
                    defaults = { formatter = "cljfmt", linter = "clj-kondo", debugger = false },
                },
                edn = {
                    formatters = {
                        cljfmt = {
                            mason = "cljfmt",
                            efm = { formatCommand = "cljfmt fix -", formatStdin = true },
                        },
                    },
                    linters = {},
                    debuggers = {},
                    defaults = { formatter = "cljfmt", linter = false, debugger = false },
                },
            },

            -- Nerd Font icons (statusline / picker rows).
            icons = {
                statusline = "", -- nf-dev-clojure
                test = "󰙨",
                build = "󰜫",
                run = "󰐊",
                deps = "󰏗",
            },
        },
    },
})
```
