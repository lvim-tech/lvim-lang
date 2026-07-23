-- lvim-lang.providers.dart: the Dart/Flutter provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes/root, the dartls catalog (NO mason — it ships with the Dart SDK), the flutter/dart
-- toolchain, the SDK requirement, and health. This module then EXTENDS the returned spec with the whole
-- of Dart's rich machinery, which is far beyond pure data:
--   * the FVM-aware toolchain (an FVM-pinned SDK at <root>/.fvm/flutter_sdk; dart derived beside flutter);
--   * notification-driven DECORATIONS (Flutter closing labels — providers.dart.labels);
--   * an alternative OUTLINE source (the Flutter widget tree — providers.dart.outline);
--   * a rich STATUSLINE (selected device + run state + run config) and a custom HEALTH section;
--   * the run lifecycle / devices / DevTools / VM service / pub command surface (providers.dart.commands
--     / .run / .daemon / .devices / .devtools / .vmservice / .pub).
--
-- dartls keeps its bespoke servers/dart.lua (it sets closingLabels / flutterOutline init options from the
-- decorations / outline config and wires their notification handlers).
--
---@module "lvim-lang.providers.dart"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")
local detect = require("lvim-lang.core.detect")
local core_toolchain = require("lvim-lang.core.toolchain")
local state = require("lvim-lang.state")

---@type LvimLangSpecData
local DATA = {
    name = "dart",
    filetypes = { "dart" },
    root_patterns = { "pubspec.yaml", ".git" },

    -- The Dart/Flutter SDK is the user's own (resolution is FVM-aware, overridden in the extend). `dart`
    -- is the required tool (dartls ships beside it); flutter is resolved but not separately surfaced.
    runtimes = {
        {
            bin = "dart",
            key = "dart",
            require = true,
            label = "Dart/Flutter SDK",
            hint = "Install the Dart or Flutter SDK and put `dart` (or `flutter`) on PATH; the Dart language "
                .. "server ships with it. Or install the Flutter SDK with `:LvimLang install`.",
        },
        { bin = "flutter", key = "flutter" },
    },

    -- dartls ships WITH the Dart SDK (no mason package). settings / init_options pass straight through;
    -- closingLabels / flutterOutline are set dynamically by servers/dart.lua from the decorations/outline.
    lsp = {
        servers = {
            dart = {
                mason = nil, -- ships with the Dart SDK
                filetypes = { "dart" },
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
                },
            },
        },
        default = "dart",
    },

    -- No per-filetype tool catalog: dartls formats natively and Flutter debugging is driven by the run
    -- lifecycle (providers.dart.dap), not an efm/mason tool.
    ft = {
        dart = { defaults = {} },
    },

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
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND ─────────────────────────────────────────────────────────────────────────────────────────

--- The dart config block.
---@return table
local function opts()
    return config.providers.dart or {}
end

--- FVM-pinned SDK binary for a root, if the `.fvm/flutter_sdk` symlink exists (unless fvm = false).
---@param root string
---@param bin string  "flutter" | "dart"
---@return string|nil
local function fvm_bin(root, bin)
    if opts().fvm == false then
        return nil
    end
    local path = table.concat({ root, ".fvm", "flutter_sdk", "bin", bin }, "/")
    return vim.fn.executable(path) == 1 and path or nil
end

--- Run the user's `flutter_lookup_cmd` and take its first output line as the flutter path.
---@return string|nil
local function lookup_flutter()
    local cmd = opts().flutter_lookup_cmd
    if type(cmd) ~= "string" or cmd == "" then
        return nil
    end
    local out = vim.fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 or type(out) ~= "table" or not out[1] then
        return nil
    end
    return vim.trim(out[1])
end

--- The `dart` binary that sits next to the resolved `flutter` in the same SDK bin dir.
---@param root string
---@return string|nil
local function dart_beside_flutter(root)
    local flutter = core_toolchain.resolve("dart", "flutter", root)
    if not flutter then
        return nil
    end
    local dart = vim.fs.joinpath(vim.fs.dirname(flutter), "dart")
    return vim.fn.executable(dart) == 1 and dart or nil
end

local tc = spec.toolchain.tools
-- flutter: explicit → lookup → the FVM-pinned SDK → PATH.
tc.flutter = {
    { kind = "path", value = detect.explicit("dart", "flutter") },
    { kind = "path", value = lookup_flutter },
    {
        kind = "path",
        value = function(root)
            return fvm_bin(root, "flutter")
        end,
    },
    { kind = "which", value = "flutter" },
}
-- dart: explicit → the FVM-pinned SDK → beside the resolved flutter → PATH (a project that only pins
-- Flutter still gets the matching Dart).
tc.dart = {
    { kind = "path", value = detect.explicit("dart", "dart") },
    {
        kind = "path",
        value = function(root)
            return fvm_bin(root, "dart")
        end,
    },
    { kind = "path", value = dart_beside_flutter },
    { kind = "which", value = "dart" },
}

-- Extra provider config the run lifecycle / installer / decorations read.
defaults.fvm = true -- honour an FVM-pinned SDK at <root>/.fvm/flutter_sdk
defaults.sdk = { repo = "https://github.com/flutter/flutter.git", ref = "stable" } -- `:LvimLang install`
defaults.outline = true -- feed the Flutter Outline (widget tree) into the lvim-lsp outline panel
defaults.decorations = { closing_labels = true, closing_labels_prefix = "// " }

-- Notification-driven decorations (Flutter closing labels) + the alternative Flutter Outline source
-- (both registered so the toggles work before the first notification; handlers live in servers/dart.lua).
spec.decorations = { require("lvim-lang.providers.dart.labels") }
spec.outline = require("lvim-lang.providers.dart.outline").spec

--- Statusline segment for a root: the Flutter marker, the selected device, the run state, and the active
--- run config. All glyphs come from config.providers.dart.icons (configurable).
---@param root string
---@return string
spec.statusline = function(root)
    local ic = opts().icons or {}
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

--- Health section: report whether the Flutter/Dart toolchain resolves, with the SDK-install hint.
---@param h table
---@return nil
spec.health = function(h)
    local root = vim.uv.cwd() or "."
    local missing = false
    for _, tool in ipairs({ "flutter", "dart" }) do
        local path, reason = core_toolchain.resolve("dart", tool, root)
        if path then
            local ver = core_toolchain.version("dart", tool, root)
            h.ok(("%s: %s%s"):format(tool, path, ver and ("  (" .. ver .. ")") or ""))
        else
            missing = true
            h.warn(("%s not found — %s"):format(tool, reason or "no strategy matched"))
        end
    end
    if missing then
        h.info("Install the Flutter SDK with `:LvimLang install` (or set providers.dart.bin_paths.flutter)")
    end
end

spec.tasks = require("lvim-lang.providers.dart.pub").templates
spec.commands = require("lvim-lang.providers.dart.commands")

registry.register(spec, defaults)

return spec
