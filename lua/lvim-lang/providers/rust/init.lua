-- lvim-lang.providers.rust: the Rust provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Built milestone by milestone; R0
-- wires the toolchain (cargo/rustc/rust-analyzer/rustfmt/clippy via rustup/mise), a health section
-- and a statusline segment. LSP (rust-analyzer), tasks, DAP (codelldb) and the rest follow.
--
-- Reuses the Go/Dart core: the canonical per-filetype catalog (core.catalog), the multi-LSP fan-out
-- (core.lsp.register_catalog) and on-demand tooling (core.ensure). The catalog below is DERIVED
-- from the mason registry (languages = Rust); rustfmt and clippy are NOT mason packages — they ship
-- with the toolchain (rustup components), and rust-analyzer formats via rustfmt natively, so the
-- default formatter/linter are `false` (formatting from the LSP, linting from `:LvimLang clippy`).
--
---@module "lvim-lang.providers.rust"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.providers.rust.toolchain")
local core_toolchain = require("lvim-lang.core.toolchain")

---@type table
local DEFAULTS = {
    -- Explicit binary paths; each wins over every other resolution strategy.
    cargo_path = nil,
    rustc_path = nil,
    rust_analyzer_path = nil,
    cargo_lookup_cmd = nil, -- shell command whose first line is the `cargo` path
    -- Version manager for the toolchain: "rustup" | "mise" | "asdf" | false | function(root, tool).
    -- Honours a project's rust-toolchain.toml / .tool-versions. Default: rustup → mise → asdf → PATH.
    version_manager = nil,

    -- LSP server catalog. rust-analyzer is the default; `default` may be a STRING or a LIST (e.g.
    -- add "bacon-ls" for background-check diagnostics alongside RA).
    lsp = {
        servers = {
            ["rust-analyzer"] = {
                mason = "rust-analyzer",
                filetypes = { "rust" },
                role = "types", -- completion / hover / definition / rename / inlay hints / format
                settings = {
                    ["rust-analyzer"] = {
                        cargo = { allFeatures = true, buildScripts = { enable = true } },
                        -- Run clippy on save for the richer lint set (RA drives it — no separate tool).
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

    -- Per-filetype catalog. rustfmt / clippy come with the toolchain (no mason), so they carry no
    -- `mason`; rust-analyzer formats via rustfmt and drives clippy (checkOnSave), so the defaults are
    -- false — formatting from the LSP, linting from `:LvimLang clippy`. bacon is an opt-in linter.
    ft = {
        rust = {
            formatters = {
                -- Toolchain rustfmt through efm (reads stdin, emits to stdout). Opt-in: RA formats by default.
                rustfmt = { efm = { formatCommand = "rustfmt --emit stdout --edition 2021", formatStdin = true } },
            },
            linters = {
                bacon = { mason = "bacon", efm = { lintCommand = "bacon --headless", lintStdin = false } },
            },
            debuggers = {
                codelldb = { mason = "codelldb" },
                cpptools = { mason = "cpptools", bin = "OpenDebugAD7" },
            },
            defaults = { formatter = false, linter = false, debugger = "codelldb" },
        },
    },

    -- (No mason codegen catalog: Rust's helper CLIs — cargo-expand, cargo-nextest — are `cargo
    -- install` tools, not mason packages, so they are checked on PATH and hinted, not auto-installed.)

    -- Statusline / picker icons (Nerd Font, all configurable).
    icons = {
        statusline = "󱘗", -- the Rust marker in the statusline segment
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗", -- cargo dependency row
    },
}

--- Health section for :checkhealth lvim-lang: report whether the Rust toolchain resolves for the
--- current working directory, and at what version.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."
    for _, tool in ipairs({ "cargo", "rustc", "rust-analyzer", "rustfmt", "clippy" }) do
        local path, reason = core_toolchain.resolve("rust", tool, root)
        local ver = path and core_toolchain.version("rust", tool, root) or nil
        if path and ver then
            h.ok(("%s: %s  (%s)"):format(tool, path, ver))
        elseif path then
            -- Resolved but not runnable — typically a rustup proxy whose component is not installed.
            h.info(
                ("%s: %s resolved but not runnable — `rustup component add %s` or install via the mason registry"):format(
                    tool,
                    path,
                    tool
                )
            )
        elseif tool == "cargo" or tool == "rustc" then
            h.warn(("%s not found — %s"):format(tool, reason or "install the Rust toolchain (rustup)"))
        else
            h.info(
                ("%s not found — a rustup component (`rustup component add %s`) or the mason registry"):format(
                    tool,
                    tool
                )
            )
        end
    end
end

--- Statusline segment for a root: the Rust marker + the active run config (if any).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.rust and config.providers.rust.icons) or {}
    local parts = { ic.statusline or "" }
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
    name = "rust",
    filetypes = { "rust" },
    root_patterns = { "Cargo.toml", "Cargo.lock", ".git" },
    statusline = statusline,
    toolchain = toolchain,
    commands = require("lvim-lang.providers.rust.commands"),
    -- lvim-tasks templates (arg-less cargo dependency subcommands) — also via :LvimLang deps.
    tasks = require("lvim-lang.providers.rust.deps").templates,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
