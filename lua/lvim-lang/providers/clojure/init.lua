-- lvim-lang.providers.clojure: the Clojure provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes (clojure + edn), the clojure-lsp catalog, the per-filetype tool catalog (cljfmt formatter
-- + clj-kondo linter), the multi-tool toolchain (clojure / clj / lein / boot / java, each honouring
-- explicit → lookup → mise/asdf/SDKMAN → PATH), the java requirement, health and statusline. This module
-- then EXTENDS the returned spec with Clojure's idiosyncratic parts:
--   * the build-tool requirement (Clojure CLI / Leiningen / Boot auto-detected — providers.clojure.buildtool)
--     and the JVM requirement (providers.clojure.jvm), composed onto the generated java one;
--   * the deps.edn run/test alias config;
--   * the CLI / lein / boot run+test command surface (providers.clojure.commands / .tasks).
--
-- clojure-lsp is a native GraalVM binary (no JVM itself); cljfmt / clj-kondo format+lint via efm and
-- clojure-lsp's own formatting is handed off on attach. clojure-lsp keeps its bespoke server-config module.
--
---@module "lvim-lang.providers.clojure"

local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")
local detect = require("lvim-lang.core.detect")
local buildtool = require("lvim-lang.providers.clojure.buildtool")
local jvm = require("lvim-lang.providers.clojure.jvm")

---@type LvimLangSpecData
local DATA = {
    name = "clojure",
    filetypes = { "clojure", "edn" },
    root_patterns = { "deps.edn", "project.clj", "build.boot", "shadow-cljs.edn", ".git" },

    -- The JVM + build tools. java is REQUIRED (Clojure runs on the JVM); the build tools (Clojure CLI /
    -- Leiningen / Boot) are resolved per project and surfaced through the build-tool requirement below.
    runtimes = {
        {
            bin = "java",
            key = "java",
            lookup_key = "java_lookup_cmd",
            sdkman = "java",
            require = true,
            label = "Java runtime (Clojure runs on the JVM)",
            hint = "Install a JDK (8+) and put `java` on PATH, or set providers.clojure.bin_paths.java; the "
                .. "Clojure CLI / Leiningen, every test run, and clojure-lsp's classpath resolution all need it.",
        },
        { bin = "clojure", key = "clojure", lookup_key = "clojure_lookup_cmd" },
        { bin = "clj", key = "clj", lookup_key = "clojure_lookup_cmd" },
        { bin = "lein", key = "lein", lookup_key = "lein_lookup_cmd", sdkman = "leiningen" },
        { bin = "boot", key = "boot", lookup_key = "boot_lookup_cmd" },
    },
    -- clojure tools use `--version` (STDOUT); java prints its banner to stderr — read both streams.
    version = detect.version_both("--version"),

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

    icons = {
        statusline = "", -- the Clojure marker in the statusline segment (nf-dev-clojure)
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        deps = "󰏗",
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND ─────────────────────────────────────────────────────────────────────────────────────────

-- How run / test invoke the Clojure CLI (deps.edn projects wire ALIASES; lein / boot ignore these).
defaults.tasks = {
    clj = {
        run_alias = "run", -- `clojure -M:run`
        test_alias = "test", -- the `:test` alias for the test runner
        test_exec = true, -- true → `clojure -X:test` (filterable); false → `clojure -M:test`
    },
}

-- Requirements: the build tool (CLI / Leiningen / Boot, detected per root) + the factory's java + the
-- JVM-version check.
local base_reqs = spec.requirements
spec.requirements = function(root)
    local reqs = { buildtool.requirement(root) }
    vim.list_extend(reqs, base_reqs and base_reqs(root) or {})
    reqs[#reqs + 1] = jvm.requirement(root)
    return reqs
end

spec.commands = require("lvim-lang.providers.clojure.commands")
spec.tasks = require("lvim-lang.providers.clojure.tasks").templates

registry.register(spec, defaults)

return spec
