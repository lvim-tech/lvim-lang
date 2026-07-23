-- lvim-lang.providers.registry.gdscript: the GDScript / Godot provider (declarative Tier 3). The LSP + debug adapter are served by a RUNNING Godot editor over TCP (LSP 6005 / DAP 6006) — a bespoke server module + an inline DAP adapter connect to them. gdformat / gdlint (gdtoolkit) format and lint. GUT is the test framework.
--
---@module "lvim-lang.providers.registry.gdscript"

---@type LvimLangSpecData
return {
    name = "gdscript",
    filetypes = { "gdscript" },
    root_patterns = { "project.godot", ".git" },
    lsp = { servers = { gdscript = { filetypes = { "gdscript" } } }, default = "gdscript" },
    ft = {
        ["gdscript"] = {
            formatters = { ["gdformat"] = { mason = "gdtoolkit", bin = "gdformat" } },
            linters = { ["gdlint"] = { mason = "gdtoolkit", bin = "gdlint" } },
            defaults = { formatter = false, linter = false },
        },
    },
    -- Godot serves a Debug Adapter on 127.0.0.1:6006 while the editor is open — connect to it (no
    -- process is launched, like the LSP on 6005), so the adapter is an inline connect function.
    dap = {
        adapters = {
            godot = function(callback)
                callback({ type = "server", host = "127.0.0.1", port = 6006 })
            end,
        },
        configurations = {
            gdscript = {
                {
                    adapter = "godot",
                    request = "launch",
                    name = "Launch (Godot editor)",
                    project = "${workspaceFolder}",
                },
            },
        },
    },
    icons = { statusline = "" },
}
