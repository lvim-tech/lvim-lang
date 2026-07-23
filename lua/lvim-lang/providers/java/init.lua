-- lvim-lang.providers.java: the Java provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Reuses the Go/Rust/Python core: the
-- per-filetype catalog (core.catalog), the LSP fan-out (core.lsp.register_catalog), the lvim-tasks
-- runner (core.runner) and on-demand tooling (core.ensure).
--
-- jdtls (the Eclipse JDT language server) is the one bespoke wrinkle: it is launched through a
-- `jdtls` wrapper that REQUIRES a per-project `-data <workspace>` directory, and it drives debugging
-- itself via the java-debug / java-test BUNDLES (their jars are handed to jdtls as init_options.bundles
-- in servers/jdtls.lua). jdtls formats Java natively, so the per-filetype efm formatter / linter
-- default to `false`; the catalog still OFFERS google-java-format (formatter) and checkstyle (linter)
-- for users who prefer efm-based tooling. build / run / test go through whichever build tool the
-- project uses — Gradle or Maven, auto-detected per root (providers.java.buildtool).
--
---@module "lvim-lang.providers.java"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.core.toolchain")
local requirements = require("lvim-lang.core.requirements")
local jdk = require("lvim-lang.providers.java.jdk")

---@type table
local DEFAULTS = {
    -- Explicit binary paths; when set each wins over every other resolution strategy.
    java_path = nil,
    jdtls_path = nil,
    -- A shell command whose first output line is the `java` binary path (checked after java_path,
    -- before the version manager / PATH). Empty by default.
    java_lookup_cmd = nil,
    -- Version manager for the JDK: "mise" | "asdf" | "sdkman" | false (ignore) | function(root).
    -- Honours the project's pinned JDK. Default: try mise, then asdf, then SDKMAN, else PATH.
    version_manager = nil,

    -- Directory under which per-project jdtls DATA workspaces are created (keyed by the sanitized
    -- project root). nil → `stdpath("cache")/jdtls`. jdtls REQUIRES a writable workspace per project.
    workspace_root = nil,

    -- Debugging: the JDWP port the build tool's remote-debug switch opens (`--debug-jvm` /
    -- `-Dmaven.surefire.debug`), and how long to wait for that test JVM before the debugger attaches.
    debug_attach_port = 5005,
    debug_attach_delay_ms = 2000,

    -- LSP server catalog. jdtls is the single Java server; its settings live under `settings.java`.
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

    -- Per-FILETYPE catalog: formatters / linters / debuggers for `java`, each with a default config,
    -- plus which is the `default` (or false = none). Only the CHOSEN tools install / wire. jdtls
    -- formats + diagnoses natively, so the efm formatter / linter default to `false`; both are still
    -- offered for users who prefer efm-based tooling
    -- (set ft.java.formatter = "google-java-format", ft.java.linter = "checkstyle").
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
                        -- checkstyle needs a ruleset; the bundled Google style is a sane default.
                        lintCommand = "checkstyle -c /google_checks.xml ${INPUT}",
                        lintStdin = false,
                        lintFormats = { "[%t%*[A-Z]] %f:%l:%c: %m", "[%t%*[A-Z]] %f:%l: %m" },
                    },
                },
            },
            debuggers = {
                -- The java-debug plugin: no standalone binary — its jars are loaded into jdtls as a
                -- bundle (see providers.java.dap.bundles). Selecting it installs the mason package so
                -- the bundle jars exist on disk.
                ["java-debug-adapter"] = { mason = "java-debug-adapter" },
            },
            defaults = { formatter = false, linter = false, debugger = "java-debug-adapter" },
        },
    },

    -- Extra tools installed UPFRONT (in the file-open installer popup) alongside the LSP/debugger:
    -- the java-test runners, whose jars jdtls loads as a bundle so single-test launching works.
    tools = { "java-test" },

    -- Nerd Font icons used in the Java provider's statusline / pickers (all configurable).
    icons = {
        statusline = "", -- the Java marker in the statusline segment
        test = "󰙨", -- test runner / result row
        build = "󰜫", -- build task row
        run = "󰐊", -- run task row
        debug = "󰃤", -- debug session row
        deps = "󰏗", -- dependency row
    },
}

--- Health section for :checkhealth lvim-lang: whether the Java toolchain (java + jdtls) resolves for
--- the current working directory, and at what version.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."
    local java, reason = toolchain.resolve("java", "java", root)
    if java then
        local ver = toolchain.version("java", "java", root)
        h.ok(("java: %s%s"):format(java, ver and ("  (" .. ver .. ")") or ""))
    else
        h.warn(("java not found — %s"):format(reason or "install a JDK or set providers.java.java_path"))
    end

    local jdtls = toolchain.resolve("java", "jdtls", root)
    if jdtls then
        h.ok(("jdtls: %s"):format(jdtls))
    else
        h.info("jdtls not found — installed on demand from the mason registry")
    end
end

--- Statusline segment for a root: the Java marker + the active run config (if any).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.java and config.providers.java.icons) or {}
    local parts = { ic.statusline or "" }
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
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
    statusline = statusline,
    toolchain = require("lvim-lang.providers.java.toolchain"),
    commands = require("lvim-lang.providers.java.commands"),
    -- lvim-tasks templates (arg-less dependency subcommands) — also runnable via :LvimLang deps.
    tasks = require("lvim-lang.providers.java.deps").templates,
    --- Surfaced at activation + in :checkhealth: a JDK must be present, and jdtls needs it to be 21+.
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
        return {
            requirements.tool_present(
                "java",
                "java",
                "Java runtime",
                "Install a JDK (21+ for jdtls) and put `java` on PATH, or set providers.java.java_path.",
                root
            ),
            jdk.requirement(root),
        }
    end,
    -- First Java buffer in a root: install the `jdt://` handler so go-to-definition into a library class
    -- (whose source jar is not attached) opens jdtls's decompiled source instead of an empty buffer.
    ---@param _root string
    ---@param _bufnr integer
    on_activate = function(_root, _bufnr)
        require("lvim-lang.providers.java.decompile").setup()
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
