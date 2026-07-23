# lvim-lang

A unified per-language development-tooling base for the lvim-tech ecosystem.

Instead of a separate plugin per language, `lvim-lang` is one **thin core** — a provider registry,
toolchain resolution, structured daemon sessions, and a notification-driven decoration engine —
into which per-language **providers** plug. The core owns none of the heavy machinery: LSP goes
through `lvim-lsp`/`lvim-ls`, process running through `lvim-tasks`, debugging through `lvim-dap`,
installation through `lvim-pkg`, and every window through `lvim-ui`. A provider is therefore
(almost) pure language semantics, and adding a language is a new `providers/<lang>` module that
self-registers — the core is never touched.

Everything is **lazy**: nothing is wired for a language until the first buffer of its filetype is
opened, at which point that project's root is resolved and the provider is activated once.

## Providers

Each provider owns a language's full tooling — LSP server(s) + settings, a per-filetype catalog of
formatters / linters / debuggers, tasks, dependencies, codegen, debugging and run configs. You pick
the active tools (or none) and override any setting; the chosen tools auto-install through the
unified `lvim-installer` popup when you open a file.

| Provider | Filetypes | LSP | Docs |
| --- | --- | --- | --- |
| Dart / Flutter | `dart` | dartls | [docs/providers/dart.md](docs/providers/dart.md) |
| Go | `go`, `gomod`, `gowork`, `gotmpl` | gopls | [docs/providers/go.md](docs/providers/go.md) |
| Rust | `rust` | rust-analyzer | [docs/providers/rust.md](docs/providers/rust.md) |
| Python | `python` | basedpyright + ruff | [docs/providers/python.md](docs/providers/python.md) |
| TypeScript / JavaScript | `typescript`, `typescriptreact`, `javascript`, `javascriptreact` | vtsls + eslint | [docs/providers/typescript.md](docs/providers/typescript.md) |
| C / C++ | `c`, `cpp`, `objc`, `objcpp` | clangd | [docs/providers/cpp.md](docs/providers/cpp.md) |
| Java | `java` | jdtls | [docs/providers/java.md](docs/providers/java.md) |
| C# / .NET | `cs` | omnisharp (roslyn opt-in) | [docs/providers/csharp.md](docs/providers/csharp.md) |
| Ruby | `ruby`, `eruby` | ruby-lsp (solargraph opt-in) | [docs/providers/ruby.md](docs/providers/ruby.md) |
| Zig | `zig`, `zir` | zls | [docs/providers/zig.md](docs/providers/zig.md) |

## Install

Install with the ecosystem's own **lvim-installer**, or with Neovim's native `vim.pack`:

```lua
vim.pack.add({ "https://github.com/lvim-tech/lvim-lang" })
require("lvim-lang").setup({})
```

## Configuration

`setup()` merges your options into the live config in place; **everything is overridable** (your
`setup()` values always win over the defaults). Below are the shared **core** options; each
provider's full `providers.<name>` block is documented on its own page (linked above).

```lua
require("lvim-lang").setup({
    -- Master switch; when false no provider activates.
    enabled = true,

    -- Shared dev-log panel. `layout = nil` inherits the global `layout` below; set it to override
    -- the placement for this panel only. A `:LvimLang log <token>` wins over both.
    dev_log = {
        layout = nil, -- nil = inherit config.layout; "bottom"|"top"|"area"|"float"|"right"|"left"
        height = 15, -- rows for a horizontal placement (bottom/top/area)
        width = 60, -- columns for a vertical placement (right/left)
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

    -- GLOBAL default placement for lvim-lang panels (each panel may override with its own `layout`;
    -- a command token wins over both). "area" docks in the lvim-msgarea zone when available.
    layout = "bottom", -- "bottom" | "top" | "area" | "float" | "right" | "left"

    -- Generic core UI icons (Nerd Font). Per-language icons live in the provider block.
    icons = {
        run_config = "󰐊",
    },

    -- Per-language option blocks (see each provider's page).
    providers = {
        -- dart   = { … },   -- docs/providers/dart.md
        -- go     = { … },   -- docs/providers/go.md
        -- rust   = { … },   -- docs/providers/rust.md
        -- python = { … },   -- docs/providers/python.md
        -- typescript = { … },   -- docs/providers/typescript.md
        -- cpp    = { … },   -- docs/providers/cpp.md
        -- java   = { … },   -- docs/providers/java.md
        -- csharp = { … },   -- docs/providers/csharp.md
        -- ruby   = { … },   -- docs/providers/ruby.md
        -- zig    = { … },   -- docs/providers/zig.md
    },
})
```

## Commands

`:LvimLang <sub> [args]` — core subcommands, plus the active buffer's provider subcommands (see the
provider pages). Completion offers the core subs merged with the current buffer's provider commands.

| Command | Description |
| --- | --- |
| `:LvimLang status` | Enabled state and registered providers |
| `:LvimLang providers` | List registered providers |
| `:LvimLang toolchain` | Resolve and report the active provider's toolchain |

## Run configurations

Named run configs live in `.lvim/lang/run.lua` — a pure-data file returning a list. `:LvimLang
config` picks the active one (remembered per project); `:LvimLang run` applies it. The fields a
config carries are provider-specific (see each provider's page).

## Statusline

`require("lvim-lang").status()` returns the active provider's segment (toolchain / run state /
active run config) for the current buffer — drop it into your statusline.

## Health

`:checkhealth lvim-lang` reports the core state, ecosystem dependencies, and each provider's own
checks (toolchain resolution).
