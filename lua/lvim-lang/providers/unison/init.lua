-- lvim-lang.providers.unison: the Unison provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS).
--
-- Unison does NOT fit the usual "SDK + language server + formatter/linter/debugger" mould, and this
-- provider is deliberately kept HONEST and LIGHTER rather than padded with tooling Unison does not
-- have. The one bespoke wrinkle is the LSP: there is no launchable Unison LSP binary — the language
-- server is served over TCP by a RUNNING UCM (the Unison Codebase Manager). Starting `ucm`
-- interactively in a codebase opens an LSP server on 127.0.0.1:5757 by default (env `UNISON_LSP_PORT`
-- overrides the port); the editor CONNECTS to it (servers/unison.lua uses vim.lsp.rpc.connect).
-- Consequences that keep this provider small and truthful:
--   * No mason package for the LSP — it is UCM's, not an installable server. `ucm` is resolved from
--     PATH / an explicit path (providers.unison.toolchain).
--   * No standard external formatter or linter (UCM's own type-checker / `update` own that inside the
--     codebase), and no DAP — so the per-filetype catalog is intentionally empty.
--   * `ucm` is interactive; only its genuinely non-interactive invocations are exposed as tasks
--     (`ucm run` / `ucm run.file` / `ucm transcript` — see providers.unison.tasks). Tests run inside
--     a UCM session or via a transcript, so there is no first-class `:LvimLang test`.
-- See docs/providers/unison.md for the full model, the caveats, and what is / isn't supported.
--
---@module "lvim-lang.providers.unison"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.core.toolchain")
local requirements = require("lvim-lang.core.requirements")

-- Per-language defaults, merged into config.providers.unison at registration (users override via
-- setup({ providers = { unison = { … } } })).
---@type table
local DEFAULTS = {
    -- Explicit `ucm` binary path; when set it wins over every other resolution strategy.
    ucm_path = nil,
    -- A shell command whose first output line is the `ucm` binary path (checked after ucm_path,
    -- before PATH). Empty by default.
    ucm_lookup_cmd = nil,

    -- The TCP endpoint the editor CONNECTS to for the LSP — i.e. where the user's running UCM serves
    -- it. `lsp_port` MUST match UCM's port (default 5757; if you set `UNISON_LSP_PORT`, set this to the
    -- same value). `lsp_host` is loopback by default (UCM binds the LSP to localhost).
    lsp_host = "127.0.0.1",
    lsp_port = 5757,

    -- LSP server catalog. The single "unison" server has NO mason package: it is served by a running
    -- UCM over TCP, so the server config (servers/unison.lua) uses a TCP-connect `cmd` instead of a
    -- launched binary. Nothing is installed for it.
    lsp = {
        servers = {
            unison = {
                mason = nil, -- served by UCM, not an installable binary
                filetypes = { "unison" },
                role = "types", -- completion / hover / definition / rename
                settings = {},
            },
        },
        default = "unison",
    },

    -- Per-FILETYPE catalog. Unison has NO standard external formatter / linter / debugger — the UCM
    -- type-checker and `update` own formatting/validation inside the codebase, and there is no DAP.
    -- The block is intentionally empty (nothing to install or wire); it exists only so the core
    -- catalog machinery has a filetype entry.
    ft = {
        unison = { defaults = {} },
    },

    -- Nerd Font icons used in the Unison provider's statusline / pickers (all configurable).
    icons = {
        statusline = "󰊕", -- the Unison marker in the statusline segment (a function glyph — Unison is functional)
        run = "󰐊", -- run task row
        transcript = "󰈙", -- transcript task row
        repl = "󰆍", -- interactive UCM row
    },
}

--- Health section for :checkhealth lvim-lang: whether `ucm` resolves for the current working
--- directory (and at what version), plus the reminder that the LSP needs a running UCM.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."
    local ucm, reason = toolchain.resolve("unison", "ucm", root)
    if ucm then
        local ver = toolchain.version("unison", "ucm", root)
        h.ok(("ucm: %s%s"):format(ucm, ver and ("  (" .. ver .. ")") or ""))
    else
        h.warn(("ucm not found — %s"):format(reason or "install Unison (UCM) and put `ucm` on PATH"))
    end
    local port = tonumber((config.providers.unison or {}).lsp_port) or 5757
    h.info(("LSP is served by a running UCM (connect to 127.0.0.1:%d) — start `ucm` in your codebase"):format(port))
end

--- Statusline segment for a root: the Unison marker. (Unison has no run-config / device state.)
---@param _root string
---@return string
local function statusline(_root)
    local ic = (config.providers.unison and config.providers.unison.icons) or {}
    return ic.statusline or ""
end

---@type LvimLangProvider
local spec = {
    name = "unison",
    filetypes = { "unison" },
    root_patterns = { ".git" },
    statusline = statusline,
    toolchain = require("lvim-lang.providers.unison.toolchain"),
    commands = require("lvim-lang.providers.unison.commands"),
    --- Surfaced at activation + in :checkhealth: `ucm` must be present, and the LSP needs a running UCM.
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
        return {
            requirements.tool_present(
                "unison",
                "ucm",
                "Unison (UCM)",
                "Install Unison and put `ucm` on PATH; run `ucm` in your codebase so the LSP on port 5757 is available.",
                root
            ),
            -- Advisory (info-only, so it never pops as an activation warning): the LSP is not a binary
            -- lvim-lang can start — it is served by the UCM the user runs themselves.
            {
                label = "Unison LSP (running UCM)",
                ok = true,
                detail = ("editor connects to %s:%d — served by an interactive `ucm`, not launched by lvim-lang"):format(
                    (config.providers.unison or {}).lsp_host or "127.0.0.1",
                    tonumber((config.providers.unison or {}).lsp_port) or 5757
                ),
                hint = "start `ucm` in your codebase before opening a Unison buffer; set UNISON_LSP_PORT to change the port.",
                severity = "info",
            },
        }
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
