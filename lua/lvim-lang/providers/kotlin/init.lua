-- lvim-lang.providers.kotlin: the Kotlin provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes/root, the kotlin-language-server catalog, the per-filetype tool catalog (ktlint as the
-- formatter AND linter, kotlin-debug-adapter), the multi-tool toolchain resolution (kotlinc / java /
-- kotlin / gradle, each honouring an explicit path → lookup command → mise/asdf/SDKMAN → PATH), the
-- kotlinc + java requirements, health and statusline. This module then EXTENDS the returned spec with
-- Kotlin's idiosyncratic parts:
--   * the JVM-VERSION requirement (the LSP / debug adapter need Java 11+ — providers.kotlin.jvm);
--   * the build-tool-aware command surface (Gradle / Maven auto-detected — providers.kotlin.commands /
--     .buildtool / .tasks / .deps) and the standalone debug adapter (providers.kotlin.dap);
--   * two debug-attach tunables seeded into the config.
--
-- The reusable strategy builders (explicit / lookup / version-manager+SDKMAN / mason / PATH) come from
-- core.detect via the factory; nothing toolchain-specific remains here. kotlin-language-server keeps its
-- bespoke servers/kotlin-language-server.lua (a real file on disk wins over the factory's generic shim).
--
---@module "lvim-lang.providers.kotlin"

local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")
local detect = require("lvim-lang.core.detect")
local jvm = require("lvim-lang.providers.kotlin.jvm")

-- Per-language defaults are produced by the factory from DATA (bin_paths / version_manager / lsp / ft /
-- icons); the two debug-attach tunables below are seeded onto them in the extend. Users override any of
-- it via setup({ providers = { kotlin = { … } } }). Explicit binary overrides live under `bin_paths`; the
-- `*_lookup_cmd` keys hold optional path-printing lookup commands.
---@type LvimLangSpecData
local DATA = {
    name = "kotlin",
    filetypes = { "kotlin" },
    root_patterns = { "build.gradle.kts", "build.gradle", "settings.gradle.kts", "settings.gradle", ".git" },

    -- JVM SDK tools (the user's own — Xcode-less, via SDKMAN / mise / asdf / PATH). kotlinc + java are
    -- REQUIRED (surfaced); kotlin + gradle are resolved but not surfaced. `-version` prints to stderr.
    runtimes = {
        {
            bin = "kotlinc",
            key = "kotlinc",
            lookup_key = "kotlin_lookup_cmd",
            sdkman = "kotlin",
            require = true,
            label = "Kotlin compiler (kotlinc)",
            hint = "Install Kotlin (e.g. via SDKMAN) and put `kotlinc` on PATH, or set providers.kotlin.bin_paths.kotlinc.",
        },
        {
            bin = "java",
            key = "java",
            lookup_key = "java_lookup_cmd",
            sdkman = "java",
            require = true,
            label = "Java runtime (for the Kotlin LSP/DAP)",
            hint = "Install a JDK (11+) and put `java` on PATH, or set providers.kotlin.bin_paths.java; the Kotlin "
                .. "language server and debug adapter both run on it.",
        },
        { bin = "kotlin", key = "kotlin", lookup_key = "kotlin_lookup_cmd", sdkman = "kotlin" },
        { bin = "gradle", key = "gradle", lookup_key = "gradle_lookup_cmd", sdkman = "gradle" },
    },
    -- kotlinc / java / gradle print their version banner to stderr with `-version`.
    version = detect.version_both("-version"),

    lsp = {
        servers = {
            ["kotlin-language-server"] = {
                mason = "kotlin-language-server",
                filetypes = { "kotlin" },
                role = "types", -- completion / hover / definition / rename / format
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

    ft = {
        kotlin = {
            formatters = {
                ktlint = {
                    mason = "ktlint",
                    efm = { formatCommand = "ktlint --format --stdin --log-level=none", formatStdin = true },
                },
                ktfmt = { mason = "ktfmt", efm = { formatCommand = "ktfmt -", formatStdin = true } },
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
                detekt = {
                    mason = "detekt",
                    efm = {
                        lintCommand = "detekt --input ${INPUT}",
                        lintStdin = false,
                        lintFormats = { "%f:%l:%c: %m" },
                    },
                },
                semgrep = {
                    mason = "semgrep",
                    efm = {
                        lintCommand = "semgrep scan --config auto --quiet --error --disable-version-check --gitlab-sast ${INPUT}",
                        lintStdin = false,
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

    icons = {
        statusline = "", -- the Kotlin marker in the statusline segment
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗",
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND ─────────────────────────────────────────────────────────────────────────────────────────

-- Debug-attach tunables: the JDWP port the build tool's remote-debug switch opens (`--debug-jvm` /
-- `-Dmaven.surefire.debug`), and how long to wait for that test JVM before the debugger attaches.
defaults.debug_attach_port = 5005
defaults.debug_attach_delay_ms = 2000

-- Requirements: the factory surfaces kotlinc + java presence; add the JVM-VERSION check (Java 11+).
local base_reqs = spec.requirements
spec.requirements = function(root)
    local list = base_reqs and base_reqs(root) or {}
    list[#list + 1] = jvm.requirement(root)
    return list
end

-- The build-tool-aware command surface (Gradle/Maven) + standalone debug adapter + dependency templates.
spec.commands = require("lvim-lang.providers.kotlin.commands")
spec.tasks = require("lvim-lang.providers.kotlin.deps").templates

registry.register(spec, defaults)

return spec
