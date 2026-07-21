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

---@class LvimLangDevLogConfig
---@field open_cmd     string                     Split command the dev-log panel opens with
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
---@field icons        LvimLangIconsConfig        Generic core UI icons (Nerd Font)
---@field providers    table<string, table>       Per-language option blocks (merged by each provider)

---@type LvimLangConfig
return {
    -- Master switch. Turned off, the FileType activation in lvim-lang.registry is a no-op
    -- for every language, so nothing (LSP, decorations, runners) is wired up.
    enabled = true,

    -- Shared dev-log panel. A provider's structured runner streams non-protocol output here
    -- (Flutter's app.log, cargo's human lines, …); the panel itself is one canonical
    -- lvim-ui.surface split, so every language's log looks and behaves identically.
    dev_log = {
        open_cmd = "botright 15split",
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
}
