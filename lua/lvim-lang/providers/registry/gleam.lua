-- lvim-lang.providers.registry.gleam: the Gleam provider (declarative Tier 2).
-- Gleam ships its OWN language server (`gleam lsp`) — no mason package; the `gleam` binary is resolved
-- through the toolchain. `gleam format` formats (efm); `gleam build` / `gleam test` (gleeunit). Gleam
-- targets Erlang/JavaScript, so no native debugger.
--
---@module "lvim-lang.providers.registry.gleam"

---@type LvimLangSpecData
return {
    name = "gleam",
    filetypes = { "gleam" },
    root_patterns = { "gleam.toml", ".git" },
    runtime = {
        bin = "gleam",
        key = "gleam",
        require = true,
        label = "Gleam",
        hint = "Install Gleam (https://gleam.run/getting-started/installing/) and put `gleam` on PATH.",
    },
    lsp = {
        servers = { gleam = { filetypes = { "gleam" }, cmd = { "gleam", "lsp" } } }, -- no mason; gleam's built-in LSP
        default = "gleam",
    },
    ft = {
        gleam = {
            formatters = { ["gleam-format"] = { efm = { formatCommand = "gleam format --stdin", formatStdin = true } } },
            linters = {},
            defaults = { formatter = false, linter = false }, -- gleam LSP formats natively
        },
    },
    commands = {
        build = { cmd = { "gleam", "build" }, tool = "gleam", group = "Build", desc = "gleam build" },
        run = { cmd = { "gleam", "run" }, tool = "gleam", group = "Run", desc = "gleam run" },
        test = { cmd = { "gleam", "test" }, tool = "gleam", group = "Test", desc = "gleam test (gleeunit)" },
    },
    icons = { statusline = "" }, -- Gleam
}
