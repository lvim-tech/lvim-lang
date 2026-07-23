-- lvim-lang.providers.kotlin.buildtool: detect the project's build tool and its invocation.
-- Kotlin projects are overwhelmingly driven by Gradle (the Kotlin DSL `build.gradle.kts` or the
-- Groovy `build.gradle`); a minority use Maven through the kotlin-maven-plugin (`pom.xml`). Every
-- runnable action (build / run / test / deps) has to pick the right one and the right binary.
-- Detection walks the project markers at the resolved root: a Gradle build script / a `gradlew`
-- wrapper → Gradle; a `pom.xml` → Maven. The wrapper is PREFERRED when present (`./gradlew` /
-- `./mvnw`) — it pins the exact tool version the project expects — else the system `gradle` / `mvn`
-- on PATH. Shared by tasks / test / deps / dap so they never disagree on the tool.
--
---@module "lvim-lang.providers.kotlin.buildtool"

local M = {}

--- Gradle project markers (any one present → a Gradle build). The Kotlin DSL scripts come first so
--- a Kotlin project is recognised from its `*.gradle.kts`.
---@type string[]
local GRADLE_MARKERS = {
    "settings.gradle.kts",
    "settings.gradle",
    "build.gradle.kts",
    "build.gradle",
    "gradlew",
}

--- Is `root/name` a readable file?
---@param root string
---@param name string
---@return boolean
local function has(root, name)
    return vim.fn.filereadable(vim.fs.joinpath(root, name)) == 1
end

--- The build tool for a root: "gradle" (a Gradle marker / wrapper) → "maven" (a `pom.xml`) → nil
--- when neither is present. Gradle is checked first so a polyglot repo with both prefers Gradle.
---@param root string
---@return "gradle"|"maven"|nil
function M.detect(root)
    for _, marker in ipairs(GRADLE_MARKERS) do
        if has(root, marker) then
            return "gradle"
        end
    end
    if has(root, "pom.xml") then
        return "maven"
    end
    return nil
end

--- The leading argv for a tool at `root`: the project's wrapper when it ships (and is executable),
--- else the system binary. Gradle → `<root>/gradlew` | `gradle`; Maven → `<root>/mvnw` | `mvn`.
--- When lvim-lang's Kotlin toolchain resolves a `gradle` (a version manager / explicit path), that
--- wins over the bare system name — the wrapper still takes precedence over everything.
---@param tool "gradle"|"maven"
---@param root string
---@return string[]
function M.base(tool, root)
    if tool == "maven" then
        local wrapper = vim.fs.joinpath(root, "mvnw")
        return { vim.fn.executable(wrapper) == 1 and wrapper or "mvn" }
    end
    local wrapper = vim.fs.joinpath(root, "gradlew")
    if vim.fn.executable(wrapper) == 1 then
        return { wrapper }
    end
    local resolved = require("lvim-lang.core.toolchain").resolve("kotlin", "gradle", root)
    return { resolved or "gradle" }
end

return M
