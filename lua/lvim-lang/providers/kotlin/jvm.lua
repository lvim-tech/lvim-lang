-- lvim-lang.providers.kotlin.jvm: the Java-runtime REQUIREMENT check for the Kotlin tooling.
-- Neither the Kotlin toolchain nor its editor tooling is self-hosting: `kotlin-language-server` and
-- `kotlin-debug-adapter` are JVM programs launched through wrapper scripts that need a `java` on the
-- host, and the KLS release requires Java 11+. This module resolves the `java` those launchers will
-- use and reads its MAJOR version, so the provider can SURFACE the requirement — in `:checkhealth`
-- and a one-time notice when a Kotlin buffer opens — instead of letting the server die with an opaque
-- "Unsupported class file major version" / exit-1. Detection only: nothing is installed or changed.
--
---@module "lvim-lang.providers.kotlin.jvm"

local toolchain = require("lvim-lang.core.toolchain")

local M = {}

--- The minimum Java MAJOR version the kotlin-language-server release accepts to RUN.
M.MIN_JAVA = 11

--- The MAJOR version from a `java -version` line: `"17.0.11"` → 17, `"1.8.0"` → 8, `"21"` → 21; nil
--- when unparseable.
---@param ver string?
---@return integer?
function M.major(ver)
    if type(ver) ~= "string" then
        return nil
    end
    local a, b = ver:match('version%s+"?(%d+)%.(%d+)')
    if not a then
        a = ver:match('version%s+"?(%d+)')
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

--- Resolve the `java` the Kotlin tooling will run on for `root` and read its major version.
---@param root string
---@return { java: string?, ver: string?, major: integer?, ok: boolean }
function M.probe(root)
    local java = toolchain.resolve("kotlin", "java", root)
    local ver = java and toolchain.version("kotlin", "java", root) or nil
    local major = M.major(ver)
    return { java = java, ver = ver, major = major, ok = major ~= nil and major >= M.MIN_JAVA }
end

--- The Java-runtime requirement for `root`, as a `core.requirements` entry — surfaced (once) as a
--- notice when a Kotlin buffer opens and in `:checkhealth lvim-lang`. Satisfied only when a `java`
--- is resolved AND is Java 11+; a resolved-but-too-old JVM is the actionable case (the LSP / debug
--- adapter will crash), so it carries a concrete hint. When NO `java` is found the "Java runtime"
--- tool_present requirement owns that message, so this check stays ok to avoid a duplicate warning.
---@param root string
---@return LvimLangRequirement
function M.requirement(root)
    local p = M.probe(root)
    local ok = (p.java == nil) or p.ok -- no java → the "Java runtime" requirement reports that; not us
    return {
        label = ("Kotlin tooling Java runtime (needs Java %d+)"):format(M.MIN_JAVA),
        ok = ok,
        detail = p.java and ("running on Java " .. (p.major and tostring(p.major) or (p.ver or "unknown"))) or nil,
        hint = (
            "Run the Kotlin LSP / debug adapter on a Java %d+ JVM (install one and set JAVA_HOME to it, "
            .. "or make it your `java`)."
        ):format(M.MIN_JAVA),
        severity = "warn",
    }
end

return M
