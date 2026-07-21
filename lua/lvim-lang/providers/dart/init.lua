-- lvim-lang.providers.dart: the Dart/Flutter provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Subsystems are added milestone by
-- milestone; M1 wires the toolchain (flutter/dart/FVM resolution), the `fvm` command, and a
-- health section. LSP, runner, decorations, outline and DAP follow.
--
---@module "lvim-lang.providers.dart"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.core.toolchain")
local state = require("lvim-lang.state")

-- Per-language defaults, merged into config.providers.dart at registration (users override via
-- setup({ providers = { dart = { … } } })).
---@type table
local DEFAULTS = {
    -- Explicit Flutter binary path; when set it wins over every other resolution strategy.
    flutter_path = nil,
    -- Explicit Dart binary path (defaults to the dart beside the resolved flutter).
    dart_path = nil,
    -- A shell command whose first output line is the Flutter binary path (checked after
    -- flutter_path, before FVM / PATH). Empty by default.
    flutter_lookup_cmd = nil,
    -- Honour an FVM-pinned SDK at <root>/.fvm/flutter_sdk. Set false to ignore FVM entirely.
    fvm = true,
    -- Flutter SDK source for `:LvimLang install` (lvim-pkg sdk handler): a git repo + channel/tag.
    sdk = {
        repo = "https://github.com/flutter/flutter.git",
        ref = "stable",
    },
    -- dartls (the Dart analysis server) configuration. `settings.dart` and `init_options` are
    -- passed straight through to the server; users override any key via
    -- setup({ providers = { dart = { lsp = { settings = { … } } } } }).
    lsp = {
        settings = {
            completeFunctionCalls = true,
            showTodos = true,
            renameFilesWithClasses = "prompt",
            updateImportsOnRename = true,
            enableSnippets = true,
            documentation = "full",
        },
        init_options = {
            onlyAnalyzeProjectsWithOpenFiles = false,
            suggestFromUnimportedLibraries = true,
            -- closingLabels / flutterOutline are set dynamically by servers/dart.lua from the
            -- decorations / outline config.
        },
    },
    -- Feed the Flutter Outline (widget tree) into the lvim-lsp outline panel instead of the
    -- plain documentSymbol list. Set false to keep the symbol outline.
    outline = true,

    -- Nerd Font icons used in the Dart provider's pickers / statusline (all configurable).
    icons = {
        device = "󰄶", -- a connected device (physical / desktop / web)
        emulator = "󰄰", -- an emulator / simulator
        fvm = "󰐊", -- an FVM Flutter SDK version row
        statusline = "󰔶", -- the Flutter marker in the statusline segment
        running = "󰐊", -- app running indicator (statusline)
        stopped = "󰓛", -- app stopped indicator (statusline)
        devtools = "󰙨", -- DevTools launcher / picker row
        platform = "󰀲", -- target-platform picker row (VM service)
    },
    -- Notification-driven decorations. Rendered by lvim-lang.core.decorations; toggle at runtime
    -- with `:LvimLang labels`.
    decorations = {
        closing_labels = true,
        closing_labels_prefix = "// ",
    },
}

--- Health section for :checkhealth lvim-lang: report whether the Flutter/Dart toolchain
--- resolves for the current working directory, and at what version.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."
    local missing = false
    for _, tool in ipairs({ "flutter", "dart" }) do
        local path, reason = toolchain.resolve("dart", tool, root)
        if path then
            local ver = toolchain.version("dart", tool, root)
            h.ok(("%s: %s%s"):format(tool, path, ver and ("  (" .. ver .. ")") or ""))
        else
            missing = true
            h.warn(("%s not found — %s"):format(tool, reason or "no strategy matched"))
        end
    end
    if missing then
        h.info("Install the Flutter SDK with `:LvimLang install` (or set providers.dart.flutter_path)")
    end
end

--- Statusline segment for a root: the Flutter marker, the selected device, the run state, and the
--- active run config. All glyphs come from config.providers.dart.icons (configurable).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.dart and config.providers.dart.icons) or {}
    local parts = { ic.statusline or "󰔶" }
    local device = require("lvim-lang.providers.dart.devices").selected(root)
    if device then
        parts[#parts + 1] = (ic.device or "󰄶") .. " " .. (device.name or device.id)
    end
    local rec = state.sessions[root]
    if rec and rec.session and rec.session:alive() then
        parts[#parts + 1] = (ic.running or "󰐊") .. " running"
    end
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
    name = "dart",
    filetypes = { "dart" },
    root_patterns = { "pubspec.yaml", ".git" },
    statusline = statusline,
    toolchain = require("lvim-lang.providers.dart.toolchain"),
    -- dartls is registered with the engine through lvim-lsp/lvim-ls; its config module lives at
    -- lvim-lang.servers.dart. `lsp = {}` in the file_types entry means no mason tool is needed
    -- (dartls ships with the Dart SDK — presence is the toolchain's / health's concern).
    lsp = {
        server = "dart",
        file_types = { filetypes = { "dart" }, lsp = {} },
        dir_prefix = "lvim-lang.servers",
    },
    -- Notification-driven decorations (registered with the engine so the toggle works before the
    -- first notification; the handler itself is wired in servers/dart.lua).
    decorations = { require("lvim-lang.providers.dart.labels") },
    -- Alternative outline source (Flutter Outline); the notification handler is in servers/dart.lua.
    outline = require("lvim-lang.providers.dart.outline").spec,
    -- lvim-tasks templates (flutter pub get / upgrade) — also runnable via :LvimLang pub.
    tasks = require("lvim-lang.providers.dart.pub").templates,
    commands = require("lvim-lang.providers.dart.commands"),
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
