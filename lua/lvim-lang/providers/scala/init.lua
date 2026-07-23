-- lvim-lang.providers.scala: the Scala provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes (scala + sbt), the metals catalog, the per-filetype tool catalog (scalafmt over efm),
-- the multi-tool toolchain (java / sbt / mill / bloop, each honouring explicit → lookup → mise/asdf/SDKMAN
-- → PATH), the java requirement, health and statusline. This module then EXTENDS the returned spec with
-- Scala's idiosyncratic parts:
--   * the JVM-version requirement (metals + its debug adapter need Java 11+ — providers.scala.jvm);
--   * the build tunables (mill module, bloop project, metals DAP attach delay);
--   * the build-tool-aware command surface (sbt / mill / bloop auto-detected — providers.scala.commands /
--     .buildtool / .dap). metals OWNS the Bloop BSP build server + its own debug adapter, so lvim-lang
--     hand-rolls no BSP client.
--
-- metals formats Scala natively (scalafmt), so the efm formatter defaults off. metals keeps its bespoke
-- servers/metals.lua (a real file wins over the generic shim).
--
---@module "lvim-lang.providers.scala"

local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")
local jvm = require("lvim-lang.providers.scala.jvm")

---@type LvimLangSpecData
local DATA = {
    name = "scala",
    filetypes = { "scala", "sbt" },
    root_patterns = { "build.sbt", "build.sc", ".git" },

    -- JVM + build tools (the user's own — SDKMAN / mise / asdf / PATH). java is REQUIRED (metals runs on
    -- it); sbt / mill / bloop are resolved per project. java / sbt print their banner to stderr.
    runtimes = {
        {
            bin = "java",
            key = "java",
            lookup_key = "java_lookup_cmd",
            sdkman = "java",
            require = true,
            label = "Java runtime (for metals)",
            hint = "Install a JDK (11+) and put `java` on PATH, or set providers.scala.bin_paths.java; the Scala "
                .. "language server (metals) and its debug adapter both run on it.",
        },
        { bin = "sbt", key = "sbt", lookup_key = "sbt_lookup_cmd", sdkman = "sbt" },
        { bin = "mill", key = "mill", lookup_key = "mill_lookup_cmd" },
        { bin = "bloop", key = "bloop", managers = {} }, -- coursier install; explicit → PATH
    },
    -- java / sbt print `-version` to stderr; mill uses `--version`. Try `-version` first, then `--version`.
    version = function(bin)
        local res = vim.system({ bin, "-version" }, { text = true }):wait()
        if res.code ~= 0 then
            res = vim.system({ bin, "--version" }, { text = true }):wait()
        end
        local text = (res.stderr or "") .. "\n" .. (res.stdout or "")
        for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
            local trimmed = vim.trim(line)
            if trimmed ~= "" then
                return trimmed
            end
        end
        return nil
    end,

    lsp = {
        servers = {
            metals = {
                mason = "metals",
                filetypes = { "scala", "sbt" },
                role = "types", -- completion / hover / definition / rename / code lenses / format
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
                    isHttpEnabled = true, -- metals doctor over HTTP
                    compilerOptions = { snippetAutoIndent = false },
                },
            },
        },
        default = "metals",
    },

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
            defaults = { formatter = false, linter = false, debugger = false },
        },
        sbt = {
            formatters = {},
            linters = {},
            debuggers = {},
            defaults = { formatter = false, linter = false, debugger = false },
        },
    },

    icons = {
        statusline = "", -- the Scala marker in the statusline segment (nf-seti-scala)
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗",
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND ─────────────────────────────────────────────────────────────────────────────────────────

-- Build / debug tunables the commands + dap read.
defaults.mill_module = nil -- mill needs a MODULE to run/test a single class (`mill <module>.run`)
defaults.bloop_project = nil -- bloop addresses a PROJECT (nil = the sanitized root basename)
defaults.debug_attach_delay_ms = 500 -- wait for metals' DAP server (started via debug-adapter-start)

-- Requirements: the factory surfaces java presence; add the JVM-VERSION check (Java 11+).
local base_reqs = spec.requirements
spec.requirements = function(root)
    local list = base_reqs and base_reqs(root) or {}
    list[#list + 1] = jvm.requirement(root)
    return list
end

spec.commands = require("lvim-lang.providers.scala.commands")
spec.tasks = require("lvim-lang.providers.scala.deps").templates

registry.register(spec, defaults)

return spec
