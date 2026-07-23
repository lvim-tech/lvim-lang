-- lvim-lang.providers.clojure.jvm: the Java-runtime REQUIREMENT check for the Clojure tooling.
-- Clojure IS a JVM language: the Clojure CLI (`clojure` / `clj`), Leiningen and every test run compile
-- to and execute on a `java`, and clojure-lsp resolves a project's classpath by shelling out to those
-- same tools — so a JVM must be present for anything to work. (clojure-lsp's own binary is a native
-- GraalVM image and does not itself need a JVM, but the classpath resolution it performs does.) Clojure
-- requires Java 8+. This module resolves the `java` those tools will use and reads its MAJOR version,
-- so the provider can SURFACE the requirement — in `:checkhealth` and a one-time notice when a Clojure
-- buffer opens — instead of letting a run / classpath resolution fail with an opaque error. Detection
-- only: nothing is installed or changed here.
--
---@module "lvim-lang.providers.clojure.jvm"

local toolchain = require("lvim-lang.core.toolchain")

local M = {}

--- The minimum Java MAJOR version Clojure supports (Clojure 1.11 / 1.12 baseline is Java 8).
M.MIN_JAVA = 8

--- The MAJOR version from a `java` version line, handling BOTH the `-version` form
--- (`java version "17.0.11"`) and the `--version` form (`java 17.0.11 2024-04-16 LTS`) — the shared
--- toolchain version hook runs `--version`, so the keyword-less form is the common one here:
--- `"17.0.11"` → 17, `"1.8.0"` → 8, `"21"` → 21; nil when unparseable. The first dotted number on the
--- line is the release (a trailing build date like `2024-04-16` uses dashes, so it never matches).
---@param ver string?
---@return integer?
function M.major(ver)
    if type(ver) ~= "string" then
        return nil
    end
    -- Prefer the `-version` "version 1.8.0" / "version \"17.0.11\"" form (unambiguous), else fall back
    -- to the first `<major>.<minor>` (`--version` form: "java 17.0.11 …"), else a bare major ("21").
    local a, b = ver:match('version%s+"?(%d+)%.(%d+)')
    if not a then
        a, b = ver:match("(%d+)%.(%d+)")
    end
    if not a then
        a = ver:match("(%d+)")
    end
    if not a then
        return nil
    end
    local major = tonumber(a)
    if major == 1 and b then -- legacy "1.8.0" scheme → the real major is the minor field
        major = tonumber(b)
    end
    return major
end

--- Resolve the `java` the Clojure tooling will run on for `root` and read its major version.
---@param root string
---@return { java: string?, ver: string?, major: integer?, ok: boolean }
function M.probe(root)
    local java = toolchain.resolve("clojure", "java", root)
    local ver = java and toolchain.version("clojure", "java", root) or nil
    local major = M.major(ver)
    return { java = java, ver = ver, major = major, ok = major ~= nil and major >= M.MIN_JAVA }
end

--- The Java-runtime requirement for `root`, as a `core.requirements` entry — surfaced (once) as a
--- notice when a Clojure buffer opens and in `:checkhealth lvim-lang`. Satisfied only when a `java`
--- is resolved AND is Java 8+; a resolved-but-too-old JVM is the actionable case (Clojure will not
--- run), so it carries a concrete hint. When NO `java` is found the "Java runtime" tool_present
--- requirement owns that message, so this check stays ok to avoid a duplicate warning.
---@param root string
---@return LvimLangRequirement
function M.requirement(root)
    local p = M.probe(root)
    local ok = (p.java == nil) or p.ok -- no java → the "Java runtime" requirement reports that; not us
    return {
        label = ("Clojure Java runtime (needs Java %d+)"):format(M.MIN_JAVA),
        ok = ok,
        detail = p.java and ("running on Java " .. (p.major and tostring(p.major) or (p.ver or "unknown"))) or nil,
        hint = ("Run Clojure on a Java %d+ JVM (install a JDK and put `java` on PATH, or set JAVA_HOME)."):format(
            M.MIN_JAVA
        ),
        severity = "warn",
    }
end

return M
