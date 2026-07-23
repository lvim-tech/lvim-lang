-- lvim-lang.providers.unison: the Unison provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes, the single "unison" LSP catalog (NO mason — the server is served over TCP by a RUNNING
-- UCM, not a launched binary), an intentionally EMPTY per-filetype catalog (Unison has no external
-- formatter / linter / debugger), the `ucm` toolchain (no version manager), the ucm requirement, health
-- and statusline. This module then EXTENDS the returned spec with Unison's honest wrinkles:
--   * the LSP TCP endpoint config (host / port the editor connects to);
--   * an advisory (info) requirement — the LSP is not a binary lvim-lang can start, but the UCM the user runs;
--   * the non-interactive `ucm run` / `run.file` / `transcript` command surface (providers.unison.commands).
--
-- The server keeps its bespoke servers/unison.lua (a TCP-connect cmd via vim.lsp.rpc.connect — a real file
-- wins over the generic shim). See docs/providers/unison.md for the full model.
--
---@module "lvim-lang.providers.unison"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")

---@type LvimLangSpecData
local DATA = {
    name = "unison",
    filetypes = { "unison" },
    root_patterns = { ".git" },

    -- `ucm` is Unison's single tool; no version manager (`managers = {}` skips the probe). Everything else
    -- (LSP / type-checker / REPL) lives inside a running `ucm`.
    runtime = {
        bin = "ucm",
        key = "ucm",
        lookup_key = "ucm_lookup_cmd",
        managers = {},
        require = true,
        label = "Unison (UCM)",
        hint = "Install Unison and put `ucm` on PATH; run `ucm` in your codebase so the LSP on port 5757 is available.",
    },

    lsp = {
        servers = {
            unison = {
                mason = nil, -- served by a running UCM over TCP, not an installable binary
                filetypes = { "unison" },
                role = "types", -- completion / hover / definition / rename
                settings = {},
            },
        },
        default = "unison",
    },

    -- Unison has NO standard external formatter / linter / debugger — the UCM type-checker and `update`
    -- own formatting/validation inside the codebase, and there is no DAP. Intentionally empty.
    ft = {
        unison = { defaults = {} },
    },

    icons = {
        statusline = "󰊕", -- the Unison marker (a function glyph — Unison is functional)
        run = "󰐊",
        transcript = "󰈙",
        repl = "󰆍",
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND ─────────────────────────────────────────────────────────────────────────────────────────

-- The TCP endpoint the editor CONNECTS to for the LSP — where the user's running UCM serves it. Must
-- match UCM's port (default 5757; if you set UNISON_LSP_PORT, set lsp_port to the same value).
defaults.lsp_host = "127.0.0.1"
defaults.lsp_port = 5757

-- Requirements: the factory surfaces `ucm`; add the advisory (info) note that the LSP is a running UCM,
-- not a binary lvim-lang can launch.
local base_reqs = spec.requirements
spec.requirements = function(root)
    local reqs = base_reqs and base_reqs(root) or {}
    local u = config.providers.unison or {}
    reqs[#reqs + 1] = {
        label = "Unison LSP (running UCM)",
        ok = true,
        detail = ("editor connects to %s:%d — served by an interactive `ucm`, not launched by lvim-lang"):format(
            u.lsp_host or "127.0.0.1",
            tonumber(u.lsp_port) or 5757
        ),
        hint = "start `ucm` in your codebase before opening a Unison buffer; set UNISON_LSP_PORT to change the port.",
        severity = "info",
    }
    return reqs
end

spec.commands = require("lvim-lang.providers.unison.commands")

registry.register(spec, defaults)

return spec
