-- lvim-lang.providers.clojure: the Clojure provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Reuses the shared core: the
-- per-filetype catalog (core.catalog), the LSP fan-out (core.lsp.register_catalog) and the lvim-tasks
-- runner (core.runner).
--
-- Clojure is a JVM language: the Clojure CLI / Leiningen and every test run compile to and execute on
-- a `java`, and clojure-lsp resolves a project's classpath by shelling out to those tools — so a JVM
-- must be present for anything to work (surfaced through providers.clojure.jvm as a requirement rather
-- than an opaque failure). clojure-lsp is the language server (a native GraalVM binary, launched
-- directly); cljfmt is the default formatter and clj-kondo the default linter, both routed through
-- efm, and clojure-lsp's own formatting is handed off to efm on attach (catalog.lsp_on_attach) so the
-- two never both format. run / test go through whichever build tool the project uses — the Clojure CLI
-- (deps.edn), Leiningen (project.clj) or Boot (build.boot), auto-detected per root
-- (providers.clojure.buildtool). There is no standard Clojure DAP, so no debugger is offered.
--
---@module "lvim-lang.providers.clojure"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.core.toolchain")
local requirements = require("lvim-lang.core.requirements")
local buildtool = require("lvim-lang.providers.clojure.buildtool")
local jvm = require("lvim-lang.providers.clojure.jvm")

---@type table
local DEFAULTS = {
    -- Explicit binary paths; when set each wins over every other resolution strategy.
    clojure_path = nil,
    clj_path = nil,
    lein_path = nil,
    boot_path = nil,
    java_path = nil,
    clojure_lsp_path = nil,
    cljfmt_path = nil,
    clj_kondo_path = nil,
    -- Shell commands whose first output line is the resolved binary path (checked after the explicit
    -- path, before the version manager / PATH). Empty by default.
    clojure_lookup_cmd = nil,
    lein_lookup_cmd = nil,
    boot_lookup_cmd = nil,
    java_lookup_cmd = nil,
    -- Version manager for the Clojure / JDK toolchain: "mise" | "asdf" | "sdkman" | false (ignore) |
    -- function(root, bin). Honours the project's pinned toolchain. Default: try mise, then asdf, then
    -- SDKMAN (for `lein` / `java` — the candidates it ships), else PATH.
    version_manager = nil,

    -- How run / test invoke the Clojure CLI (deps.edn projects), which have no canonical run/test verb
    -- — they wire ALIASES in deps.edn. Leiningen / Boot ignore these (they use `run` / `test`).
    tasks = {
        clj = {
            run_alias = "run", -- `clojure -M:run`
            test_alias = "test", -- the `:test` alias for the test runner
            -- true → `clojure -X:test` (an exec fn — the Cognitect test-runner convention, enabling
            -- per-test / per-namespace filtering); false → `clojure -M:test` (a main, no filtering).
            test_exec = true,
        },
    },

    -- LSP server catalog. clojure-lsp is the single Clojure server; its settings live under
    -- `settings["clojure-lsp"]`. It is a native GraalVM binary (needs no JVM itself), but resolves a
    -- project's classpath by shelling out to the Clojure CLI / Leiningen, which do need `java`.
    lsp = {
        servers = {
            ["clojure-lsp"] = {
                mason = "clojure-lsp",
                filetypes = { "clojure", "edn" },
                role = "types", -- completion / hover / definition / rename / format
                settings = {},
            },
        },
        default = "clojure-lsp",
    },

    -- Per-FILETYPE catalog: formatters / linters for `clojure` and `edn`, each with a default config,
    -- plus which is the `default` (or false = none). Only the CHOSEN tools install / wire. cljfmt is
    -- the canonical Clojure formatter and clj-kondo the canonical linter (both via efm); edn is data,
    -- so it gets cljfmt formatting but no linter. There is no standard Clojure debugger, so none is
    -- offered. clojure-lsp's own formatting is disabled on attach while an efm formatter is active.
    ft = {
        clojure = {
            formatters = {
                cljfmt = {
                    mason = "cljfmt",
                    -- `cljfmt fix -` reads stdin and writes the formatted source to stdout.
                    efm = { formatCommand = "cljfmt fix -", formatStdin = true },
                },
            },
            linters = {
                ["clj-kondo"] = {
                    mason = "clj-kondo",
                    efm = {
                        -- clj-kondo lints stdin (the live buffer) but takes the language + config from
                        -- the real filename (${INPUT}) — so a .clj / .cljs / .cljc / deps.edn each get
                        -- the right linters instead of being treated uniformly as clj code. It emits
                        -- `<file>:<line>:<col>: <level>: <message>`.
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

    -- Nerd Font icons used in the Clojure provider's statusline / pickers (all configurable).
    icons = {
        statusline = "", -- the Clojure marker in the statusline segment (nf-dev-clojure)
        test = "󰙨", -- test runner / result row
        build = "󰜫", -- build task row
        run = "󰐊", -- run task row
        deps = "󰏗", -- dependency row
    },
}

--- Health section for :checkhealth lvim-lang: whether the Clojure toolchain (a build tool + the JVM +
--- clojure-lsp) resolves for the current working directory, and at what version.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."

    local clojure = toolchain.resolve("clojure", "clojure", root) or toolchain.resolve("clojure", "clj", root)
    local lein = toolchain.resolve("clojure", "lein", root)
    if clojure then
        local ver = toolchain.version("clojure", "clojure", root)
        h.ok(("clojure: %s%s"):format(clojure, ver and ("  (" .. ver .. ")") or ""))
    elseif lein then
        local ver = toolchain.version("clojure", "lein", root)
        h.ok(("lein: %s%s"):format(lein, ver and ("  (" .. ver .. ")") or ""))
    else
        h.warn("no Clojure build tool found — install the Clojure CLI or Leiningen (set providers.clojure.*_path)")
    end

    local java, jreason = toolchain.resolve("clojure", "java", root)
    if java then
        local ver = toolchain.version("clojure", "java", root)
        h.ok(("java: %s%s"):format(java, ver and ("  (" .. ver .. ")") or ""))
    else
        h.warn(("java not found — %s"):format(jreason or "install a JDK (8+) — Clojure runs on the JVM"))
    end

    local lsp = toolchain.resolve("clojure", "clojure-lsp", root)
    if lsp then
        h.ok(("clojure-lsp: %s"):format(lsp))
    else
        h.info("clojure-lsp not found — installed on demand from the mason registry")
    end
end

--- Statusline segment for a root: the Clojure marker + the active run config (if any).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.clojure and config.providers.clojure.icons) or {}
    local parts = { ic.statusline or "" }
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
    name = "clojure",
    filetypes = { "clojure", "edn" },
    root_patterns = {
        "deps.edn",
        "project.clj",
        "build.boot",
        "shadow-cljs.edn",
        ".git",
    },
    statusline = statusline,
    toolchain = require("lvim-lang.providers.clojure.toolchain"),
    commands = require("lvim-lang.providers.clojure.commands"),
    -- lvim-tasks templates (arg-less run / test) — also runnable via :LvimLang run / test.
    tasks = require("lvim-lang.providers.clojure.tasks").templates,
    --- Surfaced at activation + in :checkhealth: a Clojure build tool must be present, and it (plus
    --- every test / classpath resolution) needs a Java 8+ JVM to run.
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
        return {
            buildtool.requirement(root),
            requirements.tool_present(
                "clojure",
                "java",
                "Java runtime (Clojure runs on the JVM)",
                "Install a JDK (8+) and put `java` on PATH, or set providers.clojure.java_path; the "
                    .. "Clojure CLI / Leiningen, every test run, and clojure-lsp's classpath resolution all need it.",
                root
            ),
            jvm.requirement(root),
        }
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
