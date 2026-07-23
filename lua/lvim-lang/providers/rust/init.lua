-- lvim-lang.providers.rust: the Rust provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes/root, the rust-analyzer (default) + bacon-ls (opt-in) LSP catalog, the per-filetype tool
-- catalog (rustfmt over efm + bacon linter + codelldb/cpptools debuggers), the toolchain, the requirement,
-- health and statusline. cargo / rustc / rustfmt / clippy resolve through rustup (which shares the
-- `<mgr> which <tool>` verb with mise/asdf, so it is just a `managers` list — data, not code). This module
-- then EXTENDS the returned spec with the one thing pure data cannot express — rust-analyzer resolving
-- through rustup BEFORE the mason fallback — plus the cargo build/run/test/clippy + dependency commands.
--
-- rustfmt / clippy ship with the toolchain (rustup components, no mason); rust-analyzer formats via
-- rustfmt and drives clippy (checkOnSave), so the efm formatter / linter default off. rust-analyzer keeps
-- its bespoke servers/rust-analyzer.lua; bacon-ls (no bespoke file) is served by the factory's generic shim.
--
---@module "lvim-lang.providers.rust"

local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")
local detect = require("lvim-lang.core.detect")

-- The Rust toolchain managers (rustup first, honouring rust-toolchain.toml; then mise / asdf).
local RUST_MGRS = { "rustup", "mise", "asdf" }

---@type LvimLangSpecData
local DATA = {
    name = "rust",
    filetypes = { "rust" },
    root_patterns = { "Cargo.toml", "Cargo.lock", ".git" },

    -- cargo is required; rustc / rustfmt / clippy are resolved for health but not surfaced. clippy's
    -- driver binary is `cargo-clippy`.
    runtimes = {
        {
            bin = "cargo",
            key = "cargo",
            lookup_key = "cargo_lookup_cmd",
            managers = RUST_MGRS,
            require = true,
            label = "Rust toolchain",
            hint = "Install the Rust toolchain via rustup and put `cargo` on PATH; rust-analyzer also needs the "
                .. "rust-src component (`rustup component add rust-src`).",
        },
        { bin = "rustc", key = "rustc", managers = RUST_MGRS },
        { bin = "rustfmt", key = "rustfmt", managers = RUST_MGRS },
        { bin = "cargo-clippy", key = "clippy", managers = RUST_MGRS },
    },

    lsp = {
        servers = {
            ["rust-analyzer"] = {
                mason = "rust-analyzer",
                filetypes = { "rust" },
                role = "types", -- completion / hover / definition / rename / inlay hints / format
                settings = {
                    ["rust-analyzer"] = {
                        cargo = { allFeatures = true, buildScripts = { enable = true } },
                        checkOnSave = true,
                        check = { command = "clippy" },
                        procMacro = { enable = true },
                        inlayHints = {
                            bindingModeHints = { enable = false },
                            closureReturnTypeHints = { enable = "never" },
                            lifetimeElisionHints = { enable = "never" },
                        },
                        diagnostics = { enable = true, experimental = { enable = true } },
                        lens = { enable = true },
                    },
                },
            },
            ["bacon-ls"] = {
                mason = "bacon-ls",
                filetypes = { "rust" },
                role = "diagnostics", -- background `bacon` diagnostics (alternative / companion to RA)
                settings = {},
            },
        },
        default = "rust-analyzer",
    },

    ft = {
        rust = {
            formatters = {
                -- Toolchain rustfmt through efm (reads stdin, emits to stdout). Opt-in: RA formats by default.
                rustfmt = { efm = { formatCommand = "rustfmt --emit stdout --edition 2021", formatStdin = true } },
            },
            linters = {
                bacon = { mason = "bacon", efm = { lintCommand = "bacon --headless", lintStdin = false } },
                semgrep = {
                    mason = "semgrep",
                    efm = {
                        lintCommand = "semgrep scan --config auto --quiet --error --disable-version-check --gitlab-sast ${INPUT}",
                        lintStdin = false,
                        lintFormats = { "%f:%l:%c: %m" },
                    },
                },
            },
            debuggers = {
                codelldb = { mason = "codelldb" },
                cpptools = { mason = "cpptools", bin = "OpenDebugAD7" },
            },
            defaults = { formatter = false, linter = false, debugger = "codelldb" },
        },
    },

    icons = {
        statusline = "󱘗", -- the Rust marker in the statusline segment
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗", -- cargo dependency row
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND ─────────────────────────────────────────────────────────────────────────────────────────

-- rust-analyzer resolves through rustup (the active toolchain may ship it as a component) BEFORE the
-- mason fallback (a github release). Insert the rustup/mise/asdf strategy after the explicit override.
table.insert(spec.toolchain.tools["rust-analyzer"], 2, {
    kind = "path",
    value = detect.via_version_manager("rust", "rust-analyzer", { managers = RUST_MGRS }),
})

spec.commands = require("lvim-lang.providers.rust.commands")
spec.tasks = require("lvim-lang.providers.rust.deps").templates

registry.register(spec, defaults)

return spec
