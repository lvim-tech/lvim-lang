# Java provider

The Java provider owns Java tooling through `lvim-lang`: **jdtls** (the Eclipse JDT language server),
formatters / linters routed per filetype through **efm-langserver**, `gradle` / `mvn` build / run /
test through **lvim-tasks**, JUnit test running (whole suite, current class, the method under the
cursor), dependency inspection, and **java-debug** debugging through **lvim-dap**. Everything is
resolved per project and lazy — nothing is wired until the first Java buffer is opened.

Filetypes: `java`. Project root: `settings.gradle` / `settings.gradle.kts` / `build.gradle` /
`build.gradle.kts` → `pom.xml` → `.git`.

## Toolchain

Resolved per project root (nothing is installed here — see the install popup below):

- **`java`** — an explicit `java_path` → a `java_lookup_cmd` → a **version manager** (`mise` /
  `asdf` / `sdkman`, honouring the project's pinned JDK) → `PATH`.
- **`jdtls`** — an explicit `jdtls_path` → the mason bin / `PATH`.

jdtls is launched through the `jdtls` wrapper with a per-project **`-data <workspace>`** directory
(a persistent index area), resolved under `workspace_root` (default `stdpath("cache")/jdtls`) keyed
by the sanitized project root — so each project gets its own workspace, stable across sessions.

## Build tool

Every runnable action detects the project's build tool at the root: a Gradle build script or a
`gradlew` wrapper → **Gradle**; a `pom.xml` → **Maven**. The project **wrapper** (`./gradlew` /
`./mvnw`) is preferred when present (it pins the exact tool version), else the system `gradle` /
`mvn`.

## Auto-install (the file-open popup)

Opening a Java file offers the **active** tools it needs but lacks, through the unified
`lvim-installer` popup: the **LSP server** (jdtls), the **debugger** (java-debug-adapter) and the
**java-test** runners (whose jars jdtls loads as bundles), plus a **formatter** / **linter** if you
select an efm one. All are mason-registry packages installed by `lvim-pkg`'s own handlers — no
`mason.nvim`.

## LSP server catalog

jdtls is the single Java server. Its settings live under `settings.java`. When a formatter is active
for the buffer, the LSP's own formatting is switched off automatically so the two don't both format.

| Server | Role | Filetypes |
| --- | --- | --- |
| `jdtls` (default) | types / hover / definition / rename / inlay hints / format | java |

Debugging lives in the server: jdtls loads the **java-debug** and **java-test** bundle jars (from the
mason packages, via `init_options.bundles`) and exposes `vscode.java.startDebugSession`, which the
DAP adapter drives.

## Per-filetype catalog

jdtls formats + diagnoses Java natively, so the efm **formatter** and **linter** default to `false`.
The catalog still offers efm tools — to use `google-java-format` + `checkstyle` via efm, set
`ft.java.formatter = "google-java-format"`, `ft.java.linter = "checkstyle"`.

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `java` | google-java-format | checkstyle, semgrep | java-debug-adapter | formatter=false, linter=false, debugger=java-debug-adapter |

## Commands

`:LvimLang <sub> [args]` in a Java buffer:

| Command | Description |
| --- | --- |
| `:LvimLang build [args]` | `gradle build` / `mvn compile` |
| `:LvimLang run [args]` | `gradle run` / `mvn exec:java`; applies the active run config |
| `:LvimLang test [args]` | `gradle test` / `mvn test` — the whole suite |
| `:LvimLang test-func` | run the JUnit method under the cursor (`--tests` / `-Dtest`) |
| `:LvimLang test-file` | run every JUnit test in the current class |
| `:LvimLang deps <tree\|refresh\|install>` | dependency graph / re-resolve / install |
| `:LvimLang debug` | start / continue a java-debug session |
| `:LvimLang debug-test` | debug the JUnit method under the cursor (remote-debug + attach) |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

Adding / removing a dependency is done by editing `build.gradle*` / `pom.xml` directly — Gradle and
Maven have no clean, non-destructive CLI verb for it, so `deps` exposes only the safe read/resolve
operations. `debug-test` starts the test JVM with the build tool's remote-debug switch (Gradle
`--debug-jvm` / Maven `-Dmaven.surefire.debug`) — it suspends on the JDWP port — then attaches; the
port and the attach delay are configurable.

## Run configurations

Named configs in `.lvim/lang/run.lua` (a pure-data file). `:LvimLang config` picks the active one
(remembered per project); `:LvimLang run` applies its main class / args / env.

```lua
return {
    {
        name = "app",
        main_class = "com.example.App", -- Gradle -PmainClass / Maven -Dexec.mainClass
        args = { "--server.port=8080" }, -- program arguments
        env = { SPRING_PROFILES_ACTIVE = "dev" }, -- process environment
    },
}
```

## Configuration

The complete default `providers.java` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        java = {
            -- Toolchain (explicit paths win over resolution).
            java_path = nil,
            jdtls_path = nil,
            java_lookup_cmd = nil, -- shell command whose first line is the `java` path
            version_manager = nil, -- "mise"|"asdf"|"sdkman"|false|function(root); default: mise→asdf→sdkman→PATH

            -- Per-project jdtls `-data` workspace root (nil → stdpath("cache")/jdtls).
            workspace_root = nil,

            -- Debugging: the JDWP port the build tool's remote-debug switch opens, and how long to
            -- wait for the test JVM before the debugger attaches.
            debug_attach_port = 5005,
            debug_attach_delay_ms = 2000,

            -- LSP server catalog + selection.
            lsp = {
                servers = {
                    jdtls = {
                        mason = "jdtls",
                        filetypes = { "java" },
                        role = "types",
                        settings = {
                            java = {
                                signatureHelp = { enabled = true },
                                contentProvider = { preferred = "fernflower" },
                                completion = {
                                    favoriteStaticMembers = {
                                        "org.junit.jupiter.api.Assertions.*",
                                        "org.junit.Assert.*",
                                        "org.mockito.Mockito.*",
                                        "org.assertj.core.api.Assertions.*",
                                        "java.util.Objects.requireNonNull",
                                        "java.util.Objects.requireNonNullElse",
                                    },
                                    importOrder = { "java", "javax", "com", "org" },
                                },
                                sources = {
                                    organizeImports = { starThreshold = 9999, staticStarThreshold = 9999 },
                                },
                                inlayHints = { parameterNames = { enabled = "all" } }, -- none|literals|all
                                format = { enabled = true },
                                configuration = { updateBuildConfiguration = "interactive" },
                                eclipse = { downloadSources = true },
                                maven = { downloadSources = true },
                                implementationsCodeLens = { enabled = true },
                                referencesCodeLens = { enabled = true },
                                references = { includeDecompiledSources = true },
                            },
                        },
                    },
                },
                default = "jdtls", -- string | string[] (a list attaches several LSP clients)
            },

            -- Per-filetype formatter / linter / debugger catalog + selection.
            ft = {
                java = {
                    formatters = {
                        ["google-java-format"] = {
                            mason = "google-java-format",
                            efm = { formatCommand = "google-java-format -", formatStdin = true },
                        },
                    },
                    linters = {
                        checkstyle = {
                            mason = "checkstyle",
                            efm = {
                                lintCommand = "checkstyle -c /google_checks.xml ${INPUT}",
                                lintStdin = false,
                                lintFormats = { "[%t%*[A-Z]] %f:%l:%c: %m", "[%t%*[A-Z]] %f:%l: %m" },
                            },
                        },
                    },
                    debuggers = {
                        ["java-debug-adapter"] = { mason = "java-debug-adapter" },
                    },
                    -- Only the chosen tools install / wire (false = none). jdtls formats + diagnoses.
                    defaults = { formatter = false, linter = false, debugger = "java-debug-adapter" },
                },
            },

            -- Extra tools installed upfront (the java-test runner jars jdtls loads as a bundle).
            tools = { "java-test" },

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

## Available Java packages (mason registry)

Filter `languages = Java`. In the catalog you pick from these; more exist in the registry and can be
added to the catalog.

| Category | In the catalog | Also in the registry |
| --- | --- | --- |
| LSP | jdtls | — |
| Formatter | google-java-format | — |
| Linter | checkstyle | — |
| DAP | java-debug-adapter, java-test | — |
