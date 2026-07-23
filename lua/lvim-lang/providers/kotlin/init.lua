-- lvim-lang.providers.kotlin: the Kotlin provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Reuses the shared core: the
-- per-filetype catalog (core.catalog), the LSP fan-out (core.lsp.register_catalog), the lvim-tasks
-- runner (core.runner) and on-demand tooling (core.ensure).
--
-- Kotlin is a JVM language, and none of its editor tooling is self-hosting: kotlin-language-server
-- and kotlin-debug-adapter are JVM programs launched through wrapper scripts, so a `java` (11+) must
-- be present for BOTH to run — surfaced through providers.kotlin.jvm as a requirement rather than an
-- opaque crash. Unlike Java's jdtls (debugging via bundles), the debug adapter is a STANDALONE DAP
-- server (providers.kotlin.dap). build / run / test go through whichever build tool the project uses
-- — Gradle (the norm) or Maven, auto-detected per root (providers.kotlin.buildtool). ktlint is the
-- default formatter AND linter, routed through efm; kotlin-language-server's own formatting is handed
-- off to efm on attach (catalog.lsp_on_attach) so the two never both format the buffer.
--
---@module "lvim-lang.providers.kotlin"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.core.toolchain")
local requirements = require("lvim-lang.core.requirements")
local jvm = require("lvim-lang.providers.kotlin.jvm")

---@type table
local DEFAULTS = {
    -- Explicit binary paths; when set each wins over every other resolution strategy.
    kotlin_path = nil,
    kotlinc_path = nil,
    gradle_path = nil,
    java_path = nil,
    kotlin_language_server_path = nil,
    ktlint_path = nil,
    kotlin_debug_adapter_path = nil,
    -- Shell commands whose first output line is the resolved binary path (checked after the explicit
    -- path, before the version manager / PATH). Empty by default.
    kotlin_lookup_cmd = nil,
    gradle_lookup_cmd = nil,
    java_lookup_cmd = nil,
    -- Version manager for the Kotlin / Gradle / JDK toolchain: "mise" | "asdf" | "sdkman" | false
    -- (ignore) | function(root, bin). Honours the project's pinned toolchain. Default: try mise, then
    -- asdf, then SDKMAN (the common Kotlin/Gradle/JDK manager), else PATH.
    version_manager = nil,

    -- Debugging: the JDWP port the build tool's remote-debug switch opens (`--debug-jvm` /
    -- `-Dmaven.surefire.debug`), and how long to wait for that test JVM before the debugger attaches.
    debug_attach_port = 5005,
    debug_attach_delay_ms = 2000,

    -- LSP server catalog. kotlin-language-server is the single Kotlin server; its settings live under
    -- `settings.kotlin`. It is a JVM program (needs `java`), launched through the mason wrapper.
    lsp = {
        servers = {
            ["kotlin-language-server"] = {
                mason = "kotlin-language-server",
                filetypes = { "kotlin" },
                role = "types", -- completion / hover / definition / rename / format
                settings = {
                    kotlin = {
                        -- Let the compiler infer the JVM target from the project (Gradle) toolchain.
                        compiler = { jvm = { target = "default" } },
                        completion = { snippets = { enabled = true } },
                        -- Debounce between an edit and re-linting (ms).
                        linting = { debounceTime = 250 },
                    },
                },
            },
        },
        default = "kotlin-language-server",
    },

    -- Per-FILETYPE catalog: formatters / linters / debuggers for `kotlin`, each with a default
    -- config, plus which is the `default` (or false = none). Only the CHOSEN tools install / wire.
    -- ktlint is the canonical Kotlin formatter + linter, so it is the DEFAULT for both (routed
    -- through efm); the language server's own formatting is disabled on attach while an efm formatter
    -- is active (catalog.lsp_on_attach), so they never both format.
    ft = {
        kotlin = {
            formatters = {
                ktlint = {
                    mason = "ktlint",
                    -- ktlint formats stdin and writes the result to stdout (`--log-level=none`
                    -- silences its banner so only the formatted source reaches efm).
                    efm = { formatCommand = "ktlint --format --stdin --log-level=none", formatStdin = true },
                },
            },
            linters = {
                ktlint = {
                    mason = "ktlint",
                    efm = {
                        -- ktlint lints stdin and emits `<file>:<line>:<col>: <message> (<rule>)`.
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

    -- Nerd Font icons used in the Kotlin provider's statusline / pickers (all configurable).
    icons = {
        statusline = "", -- the Kotlin marker in the statusline segment
        test = "󰙨", -- test runner / result row
        build = "󰜫", -- build task row
        run = "󰐊", -- run task row
        debug = "󰃤", -- debug session row
        deps = "󰏗", -- dependency row
    },
}

--- Health section for :checkhealth lvim-lang: whether the Kotlin toolchain (kotlin/kotlinc + the JVM
--- + kotlin-language-server) resolves for the current working directory, and at what version.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."

    local kotlinc, kreason = toolchain.resolve("kotlin", "kotlinc", root)
    if kotlinc then
        local ver = toolchain.version("kotlin", "kotlinc", root)
        h.ok(("kotlinc: %s%s"):format(kotlinc, ver and ("  (" .. ver .. ")") or ""))
    else
        h.warn(
            ("kotlinc not found — %s"):format(
                kreason or "install Kotlin (SDKMAN) or set providers.kotlin.kotlinc_path"
            )
        )
    end

    local java, jreason = toolchain.resolve("kotlin", "java", root)
    if java then
        local ver = toolchain.version("kotlin", "java", root)
        h.ok(("java: %s%s"):format(java, ver and ("  (" .. ver .. ")") or ""))
    else
        h.warn(("java not found — %s"):format(jreason or "install a JDK (11+) — the Kotlin LSP / DAP run on it"))
    end

    local kls = toolchain.resolve("kotlin", "kotlin-language-server", root)
    if kls then
        h.ok(("kotlin-language-server: %s"):format(kls))
    else
        h.info("kotlin-language-server not found — installed on demand from the mason registry")
    end
end

--- Statusline segment for a root: the Kotlin marker + the active run config (if any).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.kotlin and config.providers.kotlin.icons) or {}
    local parts = { ic.statusline or "" }
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
    name = "kotlin",
    filetypes = { "kotlin" },
    root_patterns = {
        "build.gradle.kts",
        "build.gradle",
        "settings.gradle.kts",
        "settings.gradle",
        ".git",
    },
    statusline = statusline,
    toolchain = require("lvim-lang.providers.kotlin.toolchain"),
    commands = require("lvim-lang.providers.kotlin.commands"),
    -- lvim-tasks templates (arg-less dependency subcommands) — also runnable via :LvimLang deps.
    tasks = require("lvim-lang.providers.kotlin.deps").templates,
    --- Surfaced at activation + in :checkhealth: the Kotlin toolchain must be present, and the LSP /
    --- debug adapter both need a Java 11+ JVM to run.
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
        return {
            requirements.tool_present(
                "kotlin",
                "kotlinc",
                "Kotlin compiler (kotlinc)",
                "Install Kotlin (e.g. via SDKMAN) and put `kotlinc` on PATH, or set providers.kotlin.kotlinc_path.",
                root
            ),
            requirements.tool_present(
                "kotlin",
                "java",
                "Java runtime (for the Kotlin LSP/DAP)",
                "Install a JDK (11+) and put `java` on PATH, or set providers.kotlin.java_path; the Kotlin "
                    .. "language server and debug adapter both run on it.",
                root
            ),
            jvm.requirement(root),
        }
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
