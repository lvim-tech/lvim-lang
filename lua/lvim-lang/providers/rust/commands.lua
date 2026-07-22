-- lvim-lang.providers.rust.commands: the Rust subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are core
-- subcommands in lvim-lang.commands. Grows per milestone — R3 wires the one-shot `cargo` CLI tasks
-- (build / run / test / check / clippy / fmt); dependencies, tests-under-cursor, codegen and DAP follow.
--
---@module "lvim-lang.providers.rust.commands"

local tasks = require("lvim-lang.providers.rust.tasks")
local deps = require("lvim-lang.providers.rust.deps")
local test = require("lvim-lang.providers.rust.test")
local codegen = require("lvim-lang.providers.rust.codegen")
local dap = require("lvim-lang.providers.rust.dap")
local runcfg = require("lvim-lang.core.runcfg")

---@type table<string, LvimLangCommand>
local M = {
    build = { impl = tasks.build, desc = "cargo build [args]" },
    run = { impl = tasks.run, desc = "cargo run [args] (+ active run config)" },
    test = { impl = tasks.test, desc = "cargo test [args]" },
    ["test-func"] = { impl = test.func, desc = "run the #[test] function under the cursor" },
    nextest = { impl = test.nextest, desc = "cargo nextest run [args] — the faster test runner" },
    check = { impl = tasks.check, desc = "cargo check [args]" },
    clippy = { impl = tasks.clippy, desc = "cargo clippy [args]" },
    fmt = { impl = tasks.fmt, desc = "cargo fmt [args]" },
    expand = { impl = codegen.expand, desc = "expand [item] — cargo expand macros into a scratch buffer" },
    add = { impl = deps.add, desc = "cargo add <crate[@version]> [--features …]" },
    remove = { impl = deps.remove, desc = "cargo remove <crate…>" },
    update = { impl = deps.update, desc = "cargo update [crate]" },
    deps = {
        impl = deps.command,
        desc = "deps <update|tree|fetch> — cargo dependency commands",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return arg == "" or s:find(arg, 1, true) == 1
            end, deps.subs())
        end,
    },
    debug = { impl = dap.debug, desc = "start / continue a CodeLLDB debug session (lvim-dap)" },
    ["debug-test"] = { impl = dap.debug_test, desc = "debug the test under the cursor (CodeLLDB)" },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
}

return M
