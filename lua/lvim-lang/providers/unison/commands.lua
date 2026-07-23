-- lvim-lang.providers.unison.commands: the Unison subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. Unison's surface is deliberately THIN because `ucm` is an
-- interactive codebase manager — only its genuinely non-interactive invocations are exposed (run /
-- run.file / transcript, see providers.unison.tasks). Formatting, linting, `add`/`update`, the
-- type-checker and the `test` command all live inside a running UCM session and have no honest
-- one-shot CLI form, so they are intentionally NOT surfaced here (see docs/providers/unison.md).
--
---@module "lvim-lang.providers.unison.commands"

local tasks = require("lvim-lang.providers.unison.tasks")

---@type table<string, LvimLangCommand>
local M = {
    run = { impl = tasks.run, desc = "run <main> — ucm run <main> (execute a codebase main, non-interactive)" },
    ["run-file"] = {
        impl = tasks.run_file,
        desc = "run-file [main] — ucm run.file <current .u file> [main]",
    },
    transcript = {
        impl = tasks.transcript,
        desc = "transcript [file.md] — ucm transcript (scripted/CI runs, incl. tests)",
    },
}

return M
