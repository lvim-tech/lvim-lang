# Kotlin provider

The Kotlin provider owns Kotlin tooling through `lvim-lang`: **kotlin-language-server** (LSP), Gradle /
Maven **build / run / test** through **lvim-tasks** (the project's `./gradlew` / `./mvnw` wrapper
preferred), JUnit test running (whole suite / class / method under the cursor), dependency commands,
and **kotlin-debug-adapter** debugging through **lvim-dap**. Everything is resolved per project and
lazy — nothing is wired until the first Kotlin buffer is opened.

Filetypes: `kotlin`. Project root: `build.gradle.kts` → `build.gradle` → `settings.gradle.kts` → `.git`.

## Toolchain

Kotlin is a JVM language: the language server and the debug adapter both run on **`java`**, and the
build is driven by Gradle (or Maven). Resolved per project root (explicit path wins over everything):

- **`kotlin`** / **`kotlinc`** — explicit path → `kotlin_lookup_cmd` → version manager (**mise**,
  **asdf**, **SDKMAN** — the common Kotlin/Gradle/JDK manager) → PATH.
- **`gradle`** — the project's `./gradlew` wrapper (preferred — it pins the version the project
  expects) → explicit → version manager → PATH. Maven uses `./mvnw` → `mvn`.
- **`java`** — the JVM the LSP + debug adapter run on: explicit → `java_lookup_cmd` → version manager →
  PATH. Kotlin / Gradle / the JDK are the user's **own** toolchain (not lvim-pkg-installed).
- **`kotlin-language-server`** / **`ktlint`** / **`kotlin-debug-adapter`** — explicit path → the mason
  bin → PATH.

`:checkhealth` and the activation notice surface a missing `kotlinc`, a missing **Java** runtime (the
LSP/DAP need it), and a Java that is too old.

## Auto-install (the file-open popup)

Opening a Kotlin file offers the **active** tools it lacks through the unified `lvim-installer` popup:
kotlin-language-server (LSP), the default debugger (kotlin-debug-adapter), and ktlint (the default
formatter + linter). Kotlin / Gradle / the JDK are not offered — they are the user's toolchain.

## LSP server catalog

kotlin-language-server is the single server. It is a JVM program launched through the mason wrapper, so
a Java runtime must be present.

| Server | Role | Filetypes |
| --- | --- | --- |
| `kotlin-language-server` (default) | types / hover / definition / rename / format | kotlin |

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `kotlin` | ktlint (efm) | ktlint (efm) | kotlin-debug-adapter | formatter=ktlint, linter=ktlint, debugger=kotlin-debug-adapter |

ktlint is the canonical Kotlin formatter + linter, so it is the DEFAULT for both (routed through efm);
the language server's own formatting is disabled on attach while an efm formatter is active, so they
never both format.

## Commands

`:LvimLang <sub> [args]` in a Kotlin buffer:

| Command | Description |
| --- | --- |
| `:LvimLang build [args]` | `gradle build` / `mvn compile` |
| `:LvimLang run [args]` | `gradle run` / `mvn exec:java` (+ the active run config) |
| `:LvimLang test [args]` | `gradle test` / `mvn test` — the whole suite |
| `:LvimLang test-file` | run every test in the current class |
| `:LvimLang test-func` | run the test function under the cursor |
| `:LvimLang deps <tree\|refresh\|install>` | dependency graph / re-resolve / build |
| `:LvimLang debug` | start / continue a kotlin-debug-adapter session |
| `:LvimLang debug-test` | debug the test function under the cursor (remote-debug + attach) |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

## Debugging

Debugging uses **kotlin-debug-adapter** (a standalone DAP adapter — unlike jdtls' in-server bundles).
`:LvimLang debug` launches / continues a session; `:LvimLang debug-test` starts the build tool's test
task for the method under the cursor with remote debugging enabled (Gradle `--debug-jvm` / Maven
`-Dmaven.surefire.debug`, on `debug_attach_port`) and attaches after `debug_attach_delay_ms`.

## Run configurations

Named configs in `.lvim/lang/run.lua`. `:LvimLang config` picks the active one; `:LvimLang run` applies
its args / env.

```lua
return {
    {
        name = "app",
        args = { "--profile", "dev" }, -- program arguments
        env = { ENV = "dev" },
    },
    { name = "default" },
}
```

## Configuration

The complete default `providers.kotlin` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        kotlin = {
            -- Toolchain (explicit paths win over resolution).
            kotlin_path = nil,
            kotlinc_path = nil,
            gradle_path = nil,
            java_path = nil,
            kotlin_language_server_path = nil,
            ktlint_path = nil,
            kotlin_debug_adapter_path = nil,
            kotlin_lookup_cmd = nil, -- shell command whose first line is the `kotlin`/`kotlinc` path
            gradle_lookup_cmd = nil,
            java_lookup_cmd = nil,
            version_manager = nil, -- "mise"|"asdf"|"sdkman"|false|function(root, bin); default: mise→asdf→sdkman→PATH

            -- Debugging: the JDWP port the build tool's remote-debug switch opens, and the wait before
            -- the debugger attaches to the test JVM.
            debug_attach_port = 5005,
            debug_attach_delay_ms = 2000,

            -- LSP server catalog + selection. kotlin-language-server is a JVM program (needs `java`).
            lsp = {
                servers = {
                    ["kotlin-language-server"] = {
                        mason = "kotlin-language-server",
                        filetypes = { "kotlin" },
                        role = "types",
                        settings = {
                            kotlin = {
                                compiler = { jvm = { target = "default" } },
                                completion = { snippets = { enabled = true } },
                                linting = { debounceTime = 250 },
                            },
                        },
                    },
                },
                default = "kotlin-language-server",
            },

            -- Per-filetype formatter / linter / debugger catalog + selection.
            ft = {
                kotlin = {
                    formatters = {
                        ktlint = {
                            mason = "ktlint",
                            efm = { formatCommand = "ktlint --format --stdin --log-level=none", formatStdin = true },
                        },
                    },
                    linters = {
                        ktlint = {
                            mason = "ktlint",
                            efm = {
                                lintCommand = "ktlint --stdin --log-level=none",
                                lintStdin = true,
                                lintFormats = { "%f:%l:%c: %m" },
                            },
                        },
                    },
                    debuggers = {
                        ["kotlin-debug-adapter"] = { mason = "kotlin-debug-adapter" },
                    },
                    defaults = { formatter = "ktlint", linter = "ktlint", debugger = "kotlin-debug-adapter" },
                },
            },

            -- Nerd Font icons (statusline / picker rows).
            icons = {
                statusline = "", -- nf-seti-kotlin
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
