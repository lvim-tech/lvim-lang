-- lvim-lang.providers.scala: the Scala provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Reuses the shared core: the
-- per-filetype catalog (core.catalog), the LSP fan-out (core.lsp.register_catalog), the lvim-tasks
-- runner (core.runner) and on-demand tooling (core.ensure).
--
-- metals (the Scala language server) is the one bespoke wrinkle: it is a JVM program launched through
-- the mason `metals` wrapper, so a `java` (11+) must be present for it to run — surfaced through
-- providers.scala.jvm as a requirement rather than an opaque crash. metals OWNS the build server
-- itself: it discovers the project's build (sbt / mill / bloop) and drives Bloop (its BSP build
-- server) for compilation, diagnostics, code lenses AND debugging — so lvim-lang never hand-rolls a
-- BSP client. Debugging goes through metals' own `debug-adapter-start` executeCommand (a DAP server
-- metals starts on demand over BSP — see providers.scala.dap), the canonical metals debug seam.
-- build / run / test go through whichever build tool the project uses — sbt (build.sbt) / mill
-- (build.sc) / bloop, auto-detected per root (providers.scala.buildtool). scalafmt formats through
-- efm (opt-in via a `.scalafmt.conf`); metals formats natively (it shells out to scalafmt) so the
-- efm formatter defaults to `false`, and when a user does enable it metals' own formatting is handed
-- off on attach (catalog.lsp_on_attach) so the two never both format the buffer.
--
---@module "lvim-lang.providers.scala"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.core.toolchain")
local requirements = require("lvim-lang.core.requirements")
local jvm = require("lvim-lang.providers.scala.jvm")

---@type table
local DEFAULTS = {
    -- Explicit binary paths; when set each wins over every other resolution strategy.
    sbt_path = nil,
    mill_path = nil,
    bloop_path = nil,
    java_path = nil,
    metals_path = nil,
    scalafmt_path = nil,
    -- Shell commands whose first output line is the resolved binary path (checked after the explicit
    -- path, before the version manager / PATH). Empty by default.
    sbt_lookup_cmd = nil,
    mill_lookup_cmd = nil,
    java_lookup_cmd = nil,
    -- Version manager for the Scala build / JDK toolchain: "mise" | "asdf" | "sdkman" | false
    -- (ignore) | function(root, bin). Honours the project's pinned toolchain. Default: try mise,
    -- then asdf, then SDKMAN (the common sbt / JDK manager), else PATH.
    version_manager = nil,

    -- mill needs a MODULE name to run / test a single class (`mill <module>.run`); nil → the whole
    -- suite (`mill __.test`) and a notice on `run` asking for the module. Set to your app module.
    mill_module = nil,
    -- bloop always addresses a PROJECT; nil → the sanitized project-root basename (bloop's default
    -- project name for a single-project build). Set it for a multi-project bloop workspace.
    bloop_project = nil,

    -- Debugging: how long to wait for metals' DAP server to come up before lvim-dap connects (metals
    -- starts the adapter on demand via `debug-adapter-start`; no fixed port — it returns a URI).
    debug_attach_delay_ms = 500,

    -- LSP server catalog. metals is the single Scala server; its settings live under `settings.metals`
    -- and its init_options under `init_options`. It is a JVM program (needs `java`), launched through
    -- the mason wrapper, and it manages the Bloop build server itself.
    lsp = {
        servers = {
            metals = {
                mason = "metals",
                filetypes = { "scala", "sbt" },
                role = "types", -- completion / hover / definition / rename / code lenses / format
                settings = {
                    metals = {
                        -- Surface implicits / inferred types inline (metals decorations / hovers).
                        showImplicitArguments = true,
                        showImplicitConversionsAndClasses = true,
                        showInferredType = true,
                        -- Go-to a method's super-implementation via a code lens.
                        superMethodLensesEnabled = true,
                        -- Leave syntax colouring to treesitter (metals semantic tokens off by default).
                        enableSemanticHighlighting = false,
                        -- Packages to hide from completion / symbol search (none by default).
                        excludedPackages = {},
                    },
                },
                -- metals initializationOptions. Kept minimal — metals sensibly defaults the rest; the
                -- HTTP doctor is enabled so `:LvimLang` can point at metals' diagnostics page later.
                init_options = {
                    statusBarProvider = "off", -- lvim-lang surfaces status itself, not via LSP messages
                    isHttpEnabled = true, -- metals doctor over HTTP
                    compilerOptions = { snippetAutoIndent = false },
                    -- Do NOT enable the decoration provider: metals then emits `metals/publishDecorations`
                    -- client commands that need a dedicated handler (a future core.decorations bridge).
                },
            },
        },
        default = "metals",
    },

    -- Per-FILETYPE catalog: formatters / linters / debuggers, each with a default config, plus which
    -- is the `default` (or false = none). Only the CHOSEN tools install / wire. metals formats Scala
    -- natively (shelling out to scalafmt when a `.scalafmt.conf` is present), so the efm formatter
    -- defaults to `false`; scalafmt is still OFFERED for users who prefer efm-based formatting (set
    -- ft.scala.formatter = "scalafmt"). There is no first-class standalone Scala linter (the compiler
    -- + metals own diagnostics), and metals drives debugging itself — so no efm linter / DAP package.
    ft = {
        scala = {
            formatters = {
                scalafmt = {
                    mason = "scalafmt",
                    -- scalafmt reads stdin and writes the formatted source to stdout; it auto-discovers
                    -- the project's `.scalafmt.conf`. `--non-interactive` silences its prompts so only
                    -- the formatted source reaches efm.
                    efm = { formatCommand = "scalafmt --stdin --non-interactive", formatStdin = true },
                },
            },
            linters = {},
            debuggers = {},
            defaults = { formatter = false, linter = false, debugger = false },
        },
        -- `.sbt` build files are Scala too; metals handles them, no separate formatter/linter/debugger.
        sbt = {
            formatters = {},
            linters = {},
            debuggers = {},
            defaults = { formatter = false, linter = false, debugger = false },
        },
    },

    -- Nerd Font icons used in the Scala provider's statusline / pickers (all configurable).
    icons = {
        statusline = "", -- the Scala marker in the statusline segment (nf-seti-scala)
        test = "󰙨", -- test runner / result row
        build = "󰜫", -- build task row
        run = "󰐊", -- run task row
        debug = "󰃤", -- debug session row
        deps = "󰏗", -- dependency row
    },
}

--- Health section for :checkhealth lvim-lang: whether the Scala toolchain (a build tool + the JVM +
--- metals) resolves for the current working directory, and at what version.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."

    local buildtool = require("lvim-lang.providers.scala.buildtool")
    local tool = buildtool.detect(root)
    if tool then
        local bin = buildtool.base(tool, root)[1]
        h.ok(("build tool: %s (%s)"):format(tool, bin))
    else
        h.info("no sbt / mill / bloop project at the cwd — build/run/test detect the tool per project")
    end

    local java, jreason = toolchain.resolve("scala", "java", root)
    if java then
        local ver = toolchain.version("scala", "java", root)
        h.ok(("java: %s%s"):format(java, ver and ("  (" .. ver .. ")") or ""))
    else
        h.warn(("java not found — %s"):format(jreason or "install a JDK (11+) — metals runs on it"))
    end

    local metals = toolchain.resolve("scala", "metals", root)
    if metals then
        h.ok(("metals: %s"):format(metals))
    else
        h.info("metals not found — installed on demand from the mason registry")
    end
end

--- Statusline segment for a root: the Scala marker + the active run config (if any).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.scala and config.providers.scala.icons) or {}
    local parts = { ic.statusline or "" }
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
    name = "scala",
    filetypes = { "scala", "sbt" },
    root_patterns = {
        "build.sbt",
        "build.sc",
        ".git",
    },
    statusline = statusline,
    toolchain = require("lvim-lang.providers.scala.toolchain"),
    commands = require("lvim-lang.providers.scala.commands"),
    -- lvim-tasks templates (arg-less dependency subcommands) — also runnable via :LvimLang deps.
    tasks = require("lvim-lang.providers.scala.deps").templates,
    --- Surfaced at activation + in :checkhealth: metals needs a Java 11+ JVM to run.
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
        return {
            requirements.tool_present(
                "scala",
                "java",
                "Java runtime (for metals)",
                "Install a JDK (11+) and put `java` on PATH, or set providers.scala.java_path; the Scala "
                    .. "language server (metals) and its debug adapter both run on it.",
                root
            ),
            jvm.requirement(root),
        }
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
