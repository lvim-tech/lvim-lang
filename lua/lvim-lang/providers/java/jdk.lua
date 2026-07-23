-- lvim-lang.providers.java.jdk: the Java-runtime REQUIREMENT check for jdtls.
-- jdtls runs on its OWN JVM (separate from a project's TARGET Java) and the bundled release requires
-- Java 21+. This module resolves the `java` the launcher will use and reads its MAJOR version, so the
-- provider can SURFACE the requirement — in `:checkhealth` and a one-time notice when a Java buffer
-- opens — instead of letting jdtls die with an opaque `exit code 1` / "requires at least Java 21".
-- Detection only: nothing is installed or changed here.
--
---@module "lvim-lang.providers.java.jdk"

local toolchain = require("lvim-lang.core.toolchain")

local M = {}

--- The minimum Java MAJOR version the bundled jdtls launcher accepts to RUN (not the project target).
M.MIN_JDTLS = 21

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

--- Resolve the `java` jdtls will run on for `root` and read its major version.
---@param root string
---@return { java: string?, ver: string?, major: integer?, ok: boolean }
function M.probe(root)
    local java = toolchain.resolve("java", "java", root)
    local ver = java and toolchain.version("java", "java", root) or nil
    local major = M.major(ver)
    return { java = java, ver = ver, major = major, ok = major ~= nil and major >= M.MIN_JDTLS }
end

--- The jdtls Java-runtime requirement for `root`, as a `core.requirements` entry — surfaced (once) as a
--- notice when a Java buffer opens and in `:checkhealth lvim-lang`. Satisfied only when a `java` is
--- resolved AND is Java 21+; a resolved-but-too-old JVM is the actionable case (jdtls will crash), so it
--- carries a concrete hint. When NO `java` is found the runtime check owns that message, so this stays ok.
---@param root string
---@return LvimLangRequirement
function M.requirement(root)
    local p = M.probe(root)
    local ok = (p.java == nil) or p.ok -- no java → the "Java runtime" requirement reports that; not us
    return {
        label = ("jdtls Java runtime (needs Java %d+)"):format(M.MIN_JDTLS),
        ok = ok,
        detail = p.java and ("running on Java " .. (p.major and tostring(p.major) or (p.ver or "unknown"))) or nil,
        hint = (
            "Run jdtls on a Java %d+ JVM (install one and set JAVA_HOME to it, or make it your `java`). "
            .. "Your projects can still TARGET older Java via java.configuration.runtimes."
        ):format(M.MIN_JDTLS),
        severity = "warn",
    }
end

return M
