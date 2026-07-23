-- lvim-lang.providers.clojure.buildtool: detect the project's Clojure build tool and its invocation.
-- Clojure projects are driven by one of three build tools; every runnable action (run / test) has to
-- pick the right one and the right binary. Detection walks the project markers at the resolved root:
-- a `deps.edn` → the Clojure CLI (`clojure`, the non-rlwrap binary preferred for scripting); a
-- `project.clj` → Leiningen (`lein`); a `build.boot` → Boot (`boot`). The CLI is checked first so a
-- polyglot repo carrying both a `deps.edn` and a `project.clj` prefers the modern tools.deps CLI. The
-- leading binary is resolved through core.toolchain so a version-managed toolchain and a PATH one both
-- start correctly. Shared by tasks / test so the two never disagree on the tool. Also surfaces the
-- "a Clojure build tool is present" REQUIREMENT (any one of the three satisfies it). Detection only —
-- nothing is installed here.
--
---@module "lvim-lang.providers.clojure.buildtool"

local toolchain = require("lvim-lang.core.toolchain")

local M = {}

--- Project markers → build tool, in priority order (the Clojure CLI wins a polyglot repo).
---@type { marker: string, tool: "clj"|"lein"|"boot" }[]
local MARKERS = {
    { marker = "deps.edn", tool = "clj" },
    { marker = "project.clj", tool = "lein" },
    { marker = "build.boot", tool = "boot" },
}

--- Is `root/name` a readable file?
---@param root string
---@param name string
---@return boolean
local function has(root, name)
    return vim.fn.filereadable(vim.fs.joinpath(root, name)) == 1
end

--- The build tool for a root: "clj" (a `deps.edn`) → "lein" (a `project.clj`) → "boot" (a
--- `build.boot`) → nil when none is present.
---@param root string
---@return "clj"|"lein"|"boot"|nil
function M.detect(root)
    for _, m in ipairs(MARKERS) do
        if has(root, m.marker) then
            return m.tool
        end
    end
    return nil
end

--- The leading argv for a tool at `root`, its binary resolved through core.toolchain (explicit path /
--- version manager / PATH). Clojure CLI → the `clojure` binary (falls back to the `clj` wrapper, then
--- the literal name); Leiningen → `lein`; Boot → `boot`.
---@param tool "clj"|"lein"|"boot"
---@param root string
---@return string[]
function M.base(tool, root)
    if tool == "lein" then
        return { toolchain.resolve("clojure", "lein", root) or "lein" }
    end
    if tool == "boot" then
        return { toolchain.resolve("clojure", "boot", root) or "boot" }
    end
    -- The Clojure CLI: prefer the non-rlwrap `clojure` (scripting), then the `clj` wrapper.
    local bin = toolchain.resolve("clojure", "clojure", root) or toolchain.resolve("clojure", "clj", root) or "clojure"
    return { bin }
end

--- The "a Clojure build tool is present" requirement for `root`, as a core.requirements entry — ok
--- when the Clojure CLI, Leiningen OR Boot resolves; a warning (with a hint) when none does. Surfaced
--- once when a Clojure buffer opens and in `:checkhealth lvim-lang`.
---@param root string
---@return LvimLangRequirement
function M.requirement(root)
    local clojure = toolchain.resolve("clojure", "clojure", root) or toolchain.resolve("clojure", "clj", root)
    local lein = toolchain.resolve("clojure", "lein", root)
    local boot = toolchain.resolve("clojure", "boot", root)
    local found = clojure or lein or boot
    return {
        label = "Clojure build tool (Clojure CLI, Leiningen or Boot)",
        ok = found ~= nil,
        detail = found and ("found: " .. found) or "none of clojure / clj / lein / boot found",
        hint = "Install the Clojure CLI (clojure.org/guides/install_clojure) or Leiningen and put `clojure`"
            .. " / `clj` / `lein` on PATH, or set providers.clojure.clojure_path / lein_path.",
        severity = "warn",
    }
end

return M
