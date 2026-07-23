-- lvim-lang.providers.clojure.commands: the Clojure subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. run / test go through the detected build tool (Clojure CLI /
-- Leiningen / Boot); test-func / test-file target a single `deftest` / the current namespace; config
-- picks the active run configuration. (Dependencies are declared by editing deps.edn / project.clj —
-- there is no clean, non-destructive CLI verb for them — so no `deps` subcommand is offered, and an
-- nREPL eval seam is not wired yet; see docs/providers/clojure.md.)
--
---@module "lvim-lang.providers.clojure.commands"

local tasks = require("lvim-lang.providers.clojure.tasks")
local test = require("lvim-lang.providers.clojure.test")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    run = { impl = tasks.run, desc = "clojure -M:run / lein run / boot run [args] (applies the active run config)" },
    test = { impl = tasks.test, desc = "clojure -X:test / lein test / boot test — the whole suite [args]" },
    ["test-func"] = { impl = test.func, desc = "run the deftest under the cursor" },
    ["test-file"] = { impl = test.file, desc = "run every test in the current namespace" },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
