-- lvim-lang.config: the live configuration table.
-- Holds the defaults; setup() merges user overrides into it IN PLACE (through
-- lvim-utils.utils.merge), so every require("lvim-lang.config") reader sees the effective
-- values without a restart. `config.providers.<name>` is the per-language block a provider
-- reads for its own options; the core keys above it are shared by every provider.
--
-- This file is CONFIG only — nothing here is runtime state (active sessions, resolved
-- toolchains, device caches all live in lvim-lang.state).
--
---@module "lvim-lang.config"

---@alias LvimLangLayout "bottom"|"top"|"area"|"float"|"right"|"left"

---@class LvimLangDevLogConfig
---@field layout?      LvimLangLayout             Placement override for THIS panel (nil = inherit config.layout)
---@field height       integer                    Rows for a horizontal placement (bottom/top/area)
---@field width        integer                    Columns for a vertical placement (right/left)
---@field max_lines    integer                    Ring-buffer cap per project root
---@field focus_on_open boolean                   Whether opening the panel focuses it
---@field notify_errors boolean                   Surface error lines through the canonical notifier
---@field filter?      fun(line: string): boolean Return false to drop a line from the panel

---@class LvimLangDecorationsConfig
---@field enabled      boolean                    Master switch for notification-driven decorations

---@class LvimLangProjectConfig
---@field dir          string                     Project-local config dir (unified ".lvim" namespace)
---@field run_file     string                     Run-configurations file, relative to `dir`

---@class LvimLangIconsConfig
---@field run_config   string                     Icon for a run-configuration picker row

---@class LvimLangConfig
---@field enabled      boolean                    Master switch; when false no provider activates
---@field dev_log      LvimLangDevLogConfig       Shared dev-log panel defaults
---@field decorations  LvimLangDecorationsConfig  Shared decoration defaults
---@field project      LvimLangProjectConfig      Project-local config file location
---@field statusline   boolean                    Whether providers contribute a statusline segment
---@field layout       LvimLangLayout             GLOBAL default panel placement (each panel may override)
---@field icons        LvimLangIconsConfig        Generic core UI icons (Nerd Font)
---@field disable      string[]                   Built-in provider names to SKIP at setup (so you can register your own with that name — a clean replace with no config bleed / lingering LSP server)
---@field providers    table<string, table>       Per-language option blocks (merged by each provider)
---@field companions   table<string, LvimLangCompanionConfig>  Secondary LSP servers that co-attach across many providers' filetypes (emmet / tailwind / stylelint / angular)

---@class LvimLangCompanionConfig
---@field enabled?       boolean    Register this companion (default true). false = never attached
---@field mason?         string     Mason package (also the install offered by lvim-installer)
---@field bin?           string     Executable when it differs from the mason package name
---@field cmd?           string[]   Spawn argv; a "${root}" element is replaced with the resolved project root. Default { mason }
---@field filetypes      string[]   The (cross-provider) filetypes this server co-attaches to
---@field require_root?  boolean    Only start where a `root_patterns` marker exists (config() returns nil otherwise) — for project-scoped servers (tailwind / angular)
---@field root_patterns? string[]   Markers that resolve the project root (and gate `require_root`)
---@field settings?      table      LSP `settings` (sent only when non-empty)
---@field init_options?  table      LSP `initializationOptions` (sent only when non-empty)

---@type LvimLangConfig
return {
    -- Master switch. Turned off, the FileType activation in lvim-lang.registry is a no-op
    -- for every language, so nothing (LSP, decorations, runners) is wired up.
    enabled = true,

    -- Built-in providers to SKIP at setup — the name of any built-in (e.g. "java") listed here is
    -- NOT loaded, so you can `require("lvim-lang").register(your_spec, defaults)` under that same name
    -- for a CLEAN replacement: the built-in never seeds its config or fans its LSP server out, so there
    -- is no config bleed and no lingering old server. Register your own AFTER setup().
    disable = {},

    -- Shared dev-log panel. A provider's structured runner streams non-protocol output here
    -- (Flutter's app.log, cargo's human lines, …); the panel looks and behaves identically for
    -- every language. `layout = nil` inherits the global `config.layout`; set it to override the
    -- placement for THIS panel only.
    dev_log = {
        layout = nil, -- nil = inherit config.layout; "bottom"|"top"|"area"|"float"|"right"|"left"
        height = 15, -- rows for a horizontal placement (bottom/top/area)
        width = 60, -- columns for a vertical placement (right/left)
        max_lines = 5000,
        focus_on_open = false,
        notify_errors = true,
        -- filter = function(line) return true end,  -- default: keep every line
    },

    -- Notification-driven decorations (closing labels, JSX close tags, metals decorations…)
    -- are rendered by the generic lvim-lang.core.decorations engine; this is the shared
    -- on/off switch a per-provider block can still narrow.
    decorations = {
        enabled = true,
    },

    -- Project-local configuration lives under a single unified ".lvim" namespace shared by
    -- the whole ecosystem (run configs at ".lvim/lang/run.lua"), rather than a per-plugin
    -- dotdir. (lvim-ls' legacy ".lvim-ls/" is migrated separately, later.)
    project = {
        dir = ".lvim",
        run_file = "lang/run.lua",
    },

    -- Whether a provider may contribute a statusline segment (device / run state / version).
    statusline = true,

    -- GLOBAL default placement for lvim-lang panels (the dev log today). Each panel may override
    -- it with its own `layout` (e.g. dev_log.layout), and a command token wins over both
    -- (`:LvimLang log right`). "area" docks in the lvim-msgarea zone when available, else bottom.
    ---@type LvimLangLayout
    layout = "bottom",

    -- Generic core UI icons (Nerd Font). Per-language icons live in the provider block
    -- (e.g. providers.dart.icons).
    icons = {
        run_config = "󰐊",
    },

    -- Per-language option blocks. A provider merges its own defaults in here from its
    -- init.lua at registration time (e.g. providers.dart = { … }); users override the same
    -- keys through setup({ providers = { dart = { … } } }).
    ---@type table<string, table>
    providers = {},

    -- Companion (secondary) LSP servers that co-attach across the filetypes of MANY providers —
    -- they belong to no single language, so they live here rather than in a provider block. Each is
    -- fanned to the SAME additive lvim-ls seam a provider's server uses (several clients per buffer);
    -- a `require_root` companion only starts where its marker exists (config() gate). Disable one with
    -- `enabled = false`; add your own by putting another key here. See lvim-lang.core.companions.
    ---@type table<string, LvimLangCompanionConfig>
    companions = {
        -- Emmet abbreviation expansion — wanted in every markup / component buffer, no project marker.
        ["emmet-language-server"] = {
            enabled = true,
            mason = "emmet-language-server",
            cmd = { "emmet-language-server", "--stdio" },
            filetypes = {
                "html",
                "css",
                "scss",
                "less",
                "sass",
                "javascriptreact",
                "typescriptreact",
                "vue",
                "svelte",
                "astro",
            },
        },
        -- Tailwind utility-class IntelliSense — project-scoped: only in a repo with a tailwind/postcss config.
        ["tailwindcss-language-server"] = {
            enabled = true,
            mason = "tailwindcss-language-server",
            cmd = { "tailwindcss-language-server", "--stdio" },
            filetypes = {
                "html",
                "css",
                "scss",
                "less",
                "sass",
                "javascript",
                "javascriptreact",
                "typescript",
                "typescriptreact",
                "vue",
                "svelte",
                "astro",
            },
            require_root = true,
            root_patterns = {
                "tailwind.config.js",
                "tailwind.config.cjs",
                "tailwind.config.mjs",
                "tailwind.config.ts",
                "postcss.config.js",
                "postcss.config.cjs",
            },
        },
        -- Stylelint as an LSP (diagnostics + fix) for stylesheet buffers.
        ["stylelint-lsp"] = {
            enabled = true,
            mason = "stylelint-lsp",
            cmd = { "stylelint-lsp", "--stdio" },
            filetypes = { "css", "scss", "less", "sass" },
            settings = { stylelintplus = {} },
        },
        -- Angular framework server — project-scoped (an Angular / Nx workspace). ngserver needs both its
        -- own and the project's TS probe locations; the "${root}" tokens are filled per attach.
        ["angular-language-server"] = {
            enabled = true,
            mason = "angular-language-server",
            bin = "ngserver",
            cmd = { "ngserver", "--stdio", "--tsProbeLocations", "${root}", "--ngProbeLocations", "${root}" },
            filetypes = { "typescript", "html" },
            require_root = true,
            root_patterns = { "angular.json", "project.json", "nx.json" },
        },
    },
}
