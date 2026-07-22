# Dart / Flutter provider

The Dart provider owns Flutter tooling through `lvim-lang`: **dartls** (LSP), the `flutter run
--machine` lifecycle, device / emulator selection, closing labels, the Flutter Outline, Delve-free
Dart/Flutter debugging, DevTools + the VM service, `flutter pub` and run configurations.

Filetypes: `dart`. Project root: `pubspec.yaml` → `.git`.

## Features

- **Toolchain** — resolves `flutter` / `dart` per project (explicit path → lookup command → **FVM**
  `.fvm/flutter_sdk` → PATH); `:LvimLang install` clones the Flutter SDK via `lvim-pkg`.
- **LSP** — dartls through `lvim-lsp` / `lvim-ls` (completion via `lvim-cmp`), custom methods
  (`super`, `reanalyze`, `lsp restart`).
- **Run lifecycle** — `flutter run --machine`: run / attach / hot reload / hot restart / quit /
  detach, streamed into a shared **dev-log** panel.
- **Devices / emulators** — pick a target device or launch an emulator (via `flutter daemon`); the
  choice is remembered per project.
- **Closing labels** — dartls widget closing labels as faint end-of-line decorations (toggleable).
- **Flutter Outline** — the widget tree feeds the `lvim-lsp` outline panel (instead of the plain
  symbol list).
- **Debugging** — Dart / Flutter adapters + configurations registered with `lvim-dap`.
- **DevTools + VM service** — launch DevTools, and toggle the widget inspector / debug paint /
  brightness / target platform on the running app.
- **Dependencies** — `flutter pub get` / `upgrade` through `lvim-tasks`.
- **Run configurations** — named configs in `.lvim/lang/run.lua` (flavor / target / mode /
  dart-define / device), plus a statusline segment.

## Commands

| Command | Description |
| --- | --- |
| `:LvimLang run [args]` | Pick the target device, then `flutter run --machine` (+ active run config) |
| `:LvimLang attach [args]` | `flutter attach --machine` |
| `:LvimLang reload` / `restart` | Hot reload / hot restart |
| `:LvimLang quit` / `detach` | Stop / detach the running app |
| `:LvimLang log [toggle\|clear] [bottom\|top\|area\|float\|right\|left]` | The dev-log panel (placement token) |
| `:LvimLang emulators` | List and launch an emulator |
| `:LvimLang config` | Pick the active run configuration |
| `:LvimLang devtools` | Start DevTools and open its URL |
| `:LvimLang inspect` / `paint` | Toggle the widget inspector / debug paint |
| `:LvimLang brightness` / `platform` | Flip brightness / override the target platform |
| `:LvimLang super` / `reanalyze` | dartls: go to super / reanalyze |
| `:LvimLang lsp restart` | Restart dartls |
| `:LvimLang labels` | Toggle closing-label decorations |
| `:LvimLang pub <get\|upgrade\|add\|remove\|outdated>` | Dependency commands (through lvim-tasks) |
| `:LvimLang clean` / `test` / `doctor` | `flutter clean` / `test` / `doctor -v` |
| `:LvimLang build <apk\|linux\|web\|…>` | `flutter build <target>` |
| `:LvimLang fvm` | Switch the FVM-pinned Flutter SDK |
| `:LvimLang install` | Install the Flutter SDK via lvim-pkg |

## Run configurations

Named configs in `.lvim/lang/run.lua`. `:LvimLang config` picks the active one; `:LvimLang run`
applies it.

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

## Configuration

The complete default `providers.dart` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
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

            -- dartls configuration (catalog shape; passed straight through to the server).
            lsp = {
                servers = {
                    dart = {
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
                },
                default = "dart",
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
