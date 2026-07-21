# lvim-lang

A unified per-language development-tooling base for the lvim-tech ecosystem.

Instead of a separate plugin per language, `lvim-lang` is one **thin core** — a provider
registry, toolchain resolution, structured daemon sessions, and a notification-driven decoration
engine — into which per-language **providers** plug. The core owns none of the heavy machinery:
LSP goes through `lvim-lsp`/`lvim-ls`, process running through `lvim-tasks`, debugging through
`lvim-dap`, installation through `lvim-pkg`, and every window through `lvim-ui`. A provider is
therefore (almost) pure language semantics, and adding a language is a new `providers/<lang>`
module that self-registers — the core is never touched.

Everything is **lazy**: nothing is wired for a language until the first buffer of its filetype is
opened, at which point that project's root is resolved and the provider is activated once.

The first provider is **Dart / Flutter**.

## Install

Install with the ecosystem's own **lvim-installer**, or with Neovim's native `vim.pack`:

```lua
vim.pack.add({ "https://github.com/lvim-tech/lvim-lang" })
require("lvim-lang").setup({})
```

## Features (Dart / Flutter)

- **Toolchain** — resolves `flutter` / `dart` per project (explicit path → lookup command →
  **FVM** `.fvm/flutter_sdk` → PATH); `:LvimLang install` clones the Flutter SDK via `lvim-pkg`.
- **LSP** — dartls through `lvim-lsp`/`lvim-ls` (completion via `lvim-cmp`), custom methods
  (`super`, `reanalyze`, `lsp restart`).
- **Run lifecycle** — `flutter run --machine`: run / attach / hot reload / hot restart / quit /
  detach, streamed into a shared **dev-log** panel.
- **Devices / emulators** — pick a target device or launch an emulator (via `flutter daemon`);
  the choice is remembered per project.
- **Closing labels** — dartls widget closing labels as faint end-of-line decorations (toggleable).
- **Flutter Outline** — the widget tree feeds the `lvim-lsp` outline panel (instead of the plain
  symbol list).
- **Debugging** — Dart / Flutter adapters + configurations registered with `lvim-dap`.
- **DevTools + VM service** — launch DevTools, and toggle the widget inspector / debug paint /
  brightness / target platform on the running app.
- **Dependencies** — `flutter pub get` / `upgrade` through `lvim-tasks`.
- **Run configurations** — named configs in `.lvim/lang/run.lua` (flavor / target / mode /
  dart-define / device), plus a statusline segment.

## Configuration

`setup()` merges your options into the live config in place; **everything is overridable** (your
`setup()` values always win over the defaults). The complete default configuration:

```lua
require("lvim-lang").setup({
    -- Master switch; when false no provider activates.
    enabled = true,

    -- Shared dev-log panel (a real output split — like a task/quickfix pane).
    dev_log = {
        open_cmd = "botright 15split",
        max_lines = 5000,
        focus_on_open = false,
        notify_errors = true,
        -- filter = function(line) return true end,  -- return false to drop a line
    },

    -- Notification-driven decorations (closing labels, …).
    decorations = { enabled = true },

    -- Project-local config under the unified ".lvim/<plugin>/" namespace.
    project = { dir = ".lvim", run_file = "lang/run.lua" },

    -- Whether a provider contributes a statusline segment.
    statusline = true,

    -- Generic core UI icons (Nerd Font). Per-language icons live in the provider block.
    icons = {
        run_config = "󰐊",
    },

    -- Per-language option blocks.
    providers = {
        dart = {
            -- Toolchain resolution.
            flutter_path = nil, -- explicit flutter binary (wins over everything)
            dart_path = nil, -- explicit dart binary (defaults to the dart beside flutter)
            flutter_lookup_cmd = nil, -- a shell command whose first line is the flutter path
            fvm = true, -- honour <root>/.fvm/flutter_sdk

            -- Flutter SDK source for `:LvimLang install` (lvim-pkg sdk handler).
            sdk = {
                repo = "https://github.com/flutter/flutter.git",
                ref = "stable",
            },

            -- dartls configuration (passed straight through to the server).
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
                    -- closingLabels / flutterOutline are toggled from the decorations / outline options.
                },
            },

            -- Closing-labels decorations.
            decorations = {
                closing_labels = true,
                closing_labels_prefix = "// ",
            },

            -- Feed the Flutter Outline (widget tree) into the lvim-lsp outline panel.
            outline = true,

            -- Every icon is configurable (Nerd Font).
            icons = {
                device = "󰄶",
                emulator = "󰄰",
                fvm = "󰐊",
                statusline = "󰔶",
                running = "󰐊",
                stopped = "󰓛",
                devtools = "󰙨",
                platform = "󰀲",
            },
        },
    },
})
```

## Commands

`:LvimLang <sub> [args]` — core subcommands, plus the active buffer's provider subcommands.

### Core

| Command | Description |
| --- | --- |
| `:LvimLang status` | Enabled state and registered providers |
| `:LvimLang providers` | List registered providers |
| `:LvimLang toolchain` | Resolve and report the active provider's toolchain |

### Dart / Flutter

| Command | Description |
| --- | --- |
| `:LvimLang run [args]` | `flutter run --machine` on the selected device (+ active run config) |
| `:LvimLang attach [args]` | `flutter attach --machine` |
| `:LvimLang reload` / `restart` | Hot reload / hot restart |
| `:LvimLang quit` / `detach` | Stop / detach the running app |
| `:LvimLang log [toggle\|clear]` | The dev-log panel |
| `:LvimLang devices` / `emulators` | Pick a device / launch an emulator |
| `:LvimLang config` | Pick the active run configuration |
| `:LvimLang devtools` | Start DevTools and open its URL |
| `:LvimLang inspect` / `paint` | Toggle the widget inspector / debug paint |
| `:LvimLang brightness` / `platform` | Flip brightness / override the target platform |
| `:LvimLang super` / `reanalyze` | dartls: go to super / reanalyze |
| `:LvimLang lsp restart` | Restart dartls |
| `:LvimLang labels` | Toggle closing-label decorations |
| `:LvimLang pub <get\|upgrade>` | Dependency commands (through lvim-tasks) |
| `:LvimLang fvm` | Switch the FVM-pinned Flutter SDK |
| `:LvimLang install` | Install the Flutter SDK via lvim-pkg |

## Run configurations

Named run configs live in `.lvim/lang/run.lua` — a pure-data file returning a list. `:LvimLang
config` picks the active one (remembered per project); `:LvimLang run` applies it.

```lua
return {
    {
        name = "dev",
        mode = "debug", -- "debug" | "profile" | "release"
        flavor = "dev",
    },
    {
        name = "prod",
        mode = "release",
        flavor = "prod",
        target = "lib/main_prod.dart",
        device = "flutter-tester", -- overrides the interactively-selected device
        dart_define = { API_URL = "https://api.example.com" },
        args = { "--no-sound-null-safety" },
    },
}
```

## Statusline

`require("lvim-lang").status()` returns the active provider's segment (device, run state, active
run config) for the current buffer — drop it into your statusline.

## Health

`:checkhealth lvim-lang` reports the core state, ecosystem dependencies, and each provider's
own checks (toolchain resolution).
