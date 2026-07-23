-- lvim-lang.providers.java: the Java provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes/root, the jdtls catalog, the per-filetype tool catalog (google-java-format formatter,
-- checkstyle linter, the java-debug bundle), the java-test install helper, the java toolchain (SDKMAN /
-- mise / asdf), the java requirement, health and statusline. This module then EXTENDS the returned spec
-- with Java's idiosyncratic parts:
--   * the JDK-VERSION requirement (jdtls needs Java 21+ — providers.java.jdk);
--   * the jdtls workspace + debug-attach tunables;
--   * the `jdt://` decompiled-source handler installed on first Java buffer (providers.java.decompile);
--   * the build-tool-aware command surface (Gradle / Maven — providers.java.commands / .buildtool / .dap /
--     .decompile / .refactor). jdtls drives debugging via the java-debug / java-test BUNDLES.
--
-- jdtls formats Java natively, so the efm formatter/linter default off. jdtls keeps its bespoke
-- servers/jdtls.lua (per-project `-data <workspace>` + the bundle jars as init_options.bundles).
--
---@module "lvim-lang.providers.java"

local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")
local detect = require("lvim-lang.core.detect")
local jdk = require("lvim-lang.providers.java.jdk")

---@type LvimLangSpecData
local DATA = {
    name = "java",
    filetypes = { "java" },
    root_patterns = {
        "settings.gradle",
        "settings.gradle.kts",
        "build.gradle",
        "build.gradle.kts",
        "pom.xml",
        ".git",
    },

    runtime = {
        bin = "java",
        key = "java",
        lookup_key = "java_lookup_cmd",
        sdkman = "java",
        require = true,
        label = "Java runtime",
        hint = "Install a JDK (21+ for jdtls) and put `java` on PATH, or set providers.java.bin_paths.java.",
    },
    -- `java` (and the `jdtls` launcher that wraps it) print `-version` to stderr.
    version = detect.version_both("-version"),

    lsp = {
        servers = {
            jdtls = {
                mason = "jdtls",
                filetypes = { "java" },
                role = "types", -- completion / hover / definition / rename / inlay hints / format
                settings = {
                    java = {
                        signatureHelp = { enabled = true },
                        contentProvider = { preferred = "fernflower" }, -- decompiler for library sources
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
                        inlayHints = { parameterNames = { enabled = "all" } }, -- "none"|"literals"|"all"
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
        default = "jdtls",
    },

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
                -- The java-debug plugin: no standalone binary — its jars load into jdtls as a bundle
                -- (providers.java.dap.bundles). Selecting it installs the mason package for the jars.
                ["java-debug-adapter"] = { mason = "java-debug-adapter" },
            },
            defaults = { formatter = false, linter = false, debugger = "java-debug-adapter" },
        },
    },

    -- Installed UPFRONT alongside the LSP/debugger: the java-test runners, whose jars jdtls loads as a
    -- bundle so single-test launching works.
    tools = { "java-test" },

    icons = {
        statusline = "", -- the Java marker in the statusline segment
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗",
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND ─────────────────────────────────────────────────────────────────────────────────────────

-- jdtls workspace + debug-attach tunables the server / commands / dap read.
defaults.workspace_root = nil -- per-project jdtls DATA workspaces (nil = stdpath("cache")/jdtls)
defaults.debug_attach_port = 5005 -- the JDWP port the build tool's remote-debug switch opens
defaults.debug_attach_delay_ms = 2000 -- wait for the test JVM before the debugger attaches

-- Requirements: the factory surfaces java presence; add the JDK-VERSION check (jdtls needs Java 21+).
local base_reqs = spec.requirements
spec.requirements = function(root)
    local list = base_reqs and base_reqs(root) or {}
    list[#list + 1] = jdk.requirement(root)
    return list
end

-- First Java buffer in a root: install the `jdt://` handler so go-to-definition into a library class
-- (whose source jar is not attached) opens jdtls's decompiled source instead of an empty buffer.
spec.on_activate = function(_root, _bufnr)
    require("lvim-lang.providers.java.decompile").setup()
end

spec.commands = require("lvim-lang.providers.java.commands")
spec.tasks = require("lvim-lang.providers.java.deps").templates

registry.register(spec, defaults)

return spec
