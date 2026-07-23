-- lvim-lang.providers.scala.buildtool: detect the project's build tool and its invocation.
-- Scala projects are driven by sbt (the norm — `build.sbt`), mill (`build.sc`) or, for a build that
-- only carries a generated Bloop config, bloop directly (`.bloop/`). Every runnable action (build /
-- run / test / deps) has to pick the right one and the right binary. Detection walks the project
-- markers at the resolved root: `build.sbt` → sbt; `build.sc` → mill; a `.bloop` directory → bloop.
-- sbt is checked first so a polyglot/exported repo (sbt + a generated `.bloop`) prefers sbt. The
-- project WRAPPER is PREFERRED when present (`./sbt` / `./mill`) — it pins the exact tool version the
-- project expects — else the lvim-lang toolchain (a version manager / explicit SDK), else the system
-- binary. Shared by tasks / test / deps / dap so they never disagree on the tool.
--
-- NB metals drives Bloop itself for the editor's compile/diagnostics/lenses; `bloop` HERE is only the
-- fallback build tool for direct build/run/test when neither sbt nor mill is present.
--
---@module "lvim-lang.providers.scala.buildtool"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")

local M = {}

--- The scala config block.
---@return table
local function opts()
    return config.providers.scala or {}
end

--- Is `root/name` a readable file?
---@param root string
---@param name string
---@return boolean
local function has_file(root, name)
    return vim.fn.filereadable(vim.fs.joinpath(root, name)) == 1
end

--- Is `root/name` a directory?
---@param root string
---@param name string
---@return boolean
local function has_dir(root, name)
    return vim.fn.isdirectory(vim.fs.joinpath(root, name)) == 1
end

--- The build tool for a root: "sbt" (`build.sbt`) → "mill" (`build.sc`) → "bloop" (a `.bloop/` dir)
--- → nil when none is present.
---@param root string
---@return "sbt"|"mill"|"bloop"|nil
function M.detect(root)
    if has_file(root, "build.sbt") then
        return "sbt"
    end
    if has_file(root, "build.sc") then
        return "mill"
    end
    if has_dir(root, ".bloop") then
        return "bloop"
    end
    return nil
end

--- The leading argv for a tool at `root`: the project's wrapper when it ships (and is executable),
--- else the lvim-lang-resolved binary (version manager / explicit path), else the system name.
--- sbt → `<root>/sbt` | resolved `sbt`; mill → `<root>/mill` | resolved `mill`; bloop → resolved
--- `bloop`. sbt runs are quieter with `--batch` (no interactive shell) — added by the callers, not
--- here, so the base stays a pure binary argv.
---@param tool "sbt"|"mill"|"bloop"
---@param root string
---@return string[]
function M.base(tool, root)
    if tool == "bloop" then
        return { toolchain.resolve("scala", "bloop", root) or "bloop" }
    end
    local wrapper = vim.fs.joinpath(root, tool) -- ./sbt | ./mill
    if vim.fn.executable(wrapper) == 1 then
        return { wrapper }
    end
    return { toolchain.resolve("scala", tool, root) or tool }
end

--- The bloop PROJECT name for a root: the configured `bloop_project`, else the sanitized project-root
--- basename (bloop's default project name for a single-project build).
---@param root string
---@return string
function M.project(root)
    local p = opts().bloop_project
    if type(p) == "string" and p ~= "" then
        return p
    end
    return vim.fs.basename(root)
end

--- The mill MODULE name for a root (`mill <module>.run` / `<module>.test.testOnly`): the configured
--- `mill_module`, or nil when unset (the caller falls back to the whole-suite target and notifies).
---@param root string
---@return string|nil
function M.module(root)
    local m = opts().mill_module
    if type(m) == "string" and m ~= "" then
        return m
    end
    return nil
end

return M
