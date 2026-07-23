# F# / .NET provider

The F# provider owns .NET tooling through `lvim-lang`: **FsAutoComplete** (`fsautocomplete`, the LSP),
a **Fantomas** formatter offered as a task, `dotnet` build / run / test / clean and NuGet dependency
commands through **lvim-tasks**, and **netcoredbg** debugging through **lvim-dap**. Everything is
resolved per project and lazy — nothing is wired until the first F# buffer is opened.

Filetypes: `fsharp`. Project root: nearest `*.fsproj` → `*.sln` → `paket.dependencies` → `.git`.

> Root markers are GLOBS (`*.fsproj` / `*.sln`) plus the literal `paket.dependencies`. `vim.fs.root`
> cannot take globs as literal marker strings, but it DOES accept a FUNCTION matcher, so the
> provider's `root_patterns` is a predicate
> (`name:match("%.fsproj$") or name:match("%.sln$") or name == "paket.dependencies" or name == ".git"`).

## Toolchain

Resolved per project root (nothing is installed here — see the install popup below):

- **`dotnet`** — an explicit `dotnet_path` → a `dotnet_lookup_cmd` → a **version manager**
  (`mise` / `asdf`, honouring the project's pinned SDK) → `PATH`.
- **`fsautocomplete`** / **`fantomas`** / **`netcoredbg`** — an explicit path → the mason bin
  directory (where the installer drops them) → `PATH`.

## LSP: FsAutoComplete

**FsAutoComplete** (`fsautocomplete`) is the F# language server — a plain stdio LSP that works out of
the box. It is configured through LSP **settings** under the `FSharp` namespace (inlay hints, line
lens, analyzers, …) and **formats F# natively through its bundled Fantomas**, so the default efm
formatter is `false` (efm is engaged only if you opt one in).

| Server | Role | Notes |
| --- | --- | --- |
| `fsautocomplete` (default) | types / hover / definition / rename / format | stdio LSP; settings under `FSharp.*` |

## Per-filetype catalog

The `fsharp` filetype has its own catalog; you pick a default (or `false` for none). Only the chosen
tools are installed / wired. Formatting is done by the **LSP** natively (bundled Fantomas), so the
default formatter is `false`. Standalone Fantomas is available as the `:LvimLang format` **task**
(Fantomas formats files in place — it has no stdin mode — so it does not fit efm's stdin contract; a
task is the clean mechanism, and the binary installs on demand the first time you run it).

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `fsharp` | — (Fantomas via `:LvimLang format` task) | — | netcoredbg | formatter=false, linter=false, debugger=netcoredbg |

## Commands

`:LvimLang <sub> [args]` in an F# buffer:

| Command | Description |
| --- | --- |
| `:LvimLang build [args]` | `dotnet build` |
| `:LvimLang run [args]` | `dotnet run`; applies the active run config |
| `:LvimLang test [args]` | `dotnet test` |
| `:LvimLang test-func` | run the `[<Fact>]`/`[<Theory>]`/`[<Test>]`/… binding under the cursor (`--filter FullyQualifiedName~<name>`) |
| `:LvimLang test-file` | `dotnet test` every attributed test in the current buffer |
| `:LvimLang clean [args]` | `dotnet clean` |
| `:LvimLang format [paths…]` | Fantomas — format the current file (or the given paths) |
| `:LvimLang add <package[@version]> [args]` | `dotnet add package` |
| `:LvimLang remove <package>` | `dotnet remove package` |
| `:LvimLang restore [args]` | `dotnet restore` |
| `:LvimLang deps <restore\|list>` | NuGet dependency commands (`dotnet restore` / `dotnet list package`) |
| `:LvimLang debug` | start / continue a netcoredbg session |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

## Testing

Test discovery (`:LvimLang test-func` / `test-file`, and the lvim-test adapter) uses treesitter: an
attributed `let` binding — `[<Fact>]` / `[<Theory>]` (xUnit), `[<Test>]` / `[<TestCase>]` (NUnit),
`[<Property>]` (FsCheck) — is recognised whether it sits in a module body or at a namespace's top
level. The **combinator style** (Expecto `testCase "…"` inside a `testList`) is not statically
discoverable — run `:LvimLang test` (the whole project) for those suites.

## Debugging (netcoredbg)

`:LvimLang debug` continues / starts a session. Two base configurations are registered: **Launch**
(prompts for the built DLL, default `bin/Debug/…`) and **Attach to process** (pick a running
process). Per-test debugging is not offered — the .NET test host runs out-of-process, so a test is
debugged by attaching to its `dotnet test` process.

## Run configurations

Named configs in `.lvim/lang/run.lua` (a pure-data file). `:LvimLang config` picks the active one
(remembered per project); `:LvimLang run` applies its project / configuration / args / env.

```lua
return {
    {
        name = "api",
        project = "src/Api/Api.fsproj", -- --project
        configuration = "Debug", -- -c Debug
        dotnet_flags = { "--no-restore" }, -- extra `dotnet run` flags
        args = { "--urls", "http://localhost:5000" }, -- program arguments (after --)
        env = { ASPNETCORE_ENVIRONMENT = "Development" },
    },
    { name = "cli", project = "src/Cli/Cli.fsproj" },
}
```

## Configuration

The complete default `providers.fsharp` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        fsharp = {
            -- Toolchain (explicit paths win over resolution).
            dotnet_path = nil,
            fsautocomplete_path = nil,
            fantomas_path = nil,
            netcoredbg_path = nil,
            dotnet_lookup_cmd = nil, -- shell command whose first line is the `dotnet` path
            version_manager = nil, -- "mise" | "asdf" | false | function(root); default: mise→asdf→PATH

            -- LSP server catalog + selection.
            lsp = {
                servers = {
                    fsautocomplete = {
                        mason = "fsautocomplete",
                        bin = "fsautocomplete",
                        filetypes = { "fsharp" },
                        role = "types",
                        -- FsAutoComplete is configured via LSP settings under the `FSharp` namespace.
                        settings = {
                            FSharp = {
                                keywordsAutocomplete = true,
                                ExternalAutocomplete = false,
                                inlayHints = { enabled = true, typeAnnotations = true, parameterNames = true },
                                lineLens = { enabled = "replaceCodeLens", prefix = "// " },
                                enableAnalyzers = true,
                                fsac = { conserveMemory = false },
                            },
                        },
                    },
                },
                default = "fsautocomplete", -- string | string[]
            },

            -- Per-filetype formatter / linter / debugger catalog + selection.
            ft = {
                fsharp = {
                    -- FsAutoComplete formats F# natively (bundled Fantomas); standalone Fantomas is the
                    -- `:LvimLang format` task rather than an efm formatter (Fantomas has no stdin mode).
                    formatters = {},
                    linters = {},
                    debuggers = {
                        netcoredbg = { mason = "netcoredbg" },
                    },
                    defaults = { formatter = false, linter = false, debugger = "netcoredbg" },
                },
            },

            -- Statusline / picker icons (Nerd Font).
            icons = {
                statusline = "", -- nf-dev-fsharp
                test = "󰙨",
                build = "󰜫",
                run = "󰐊",
                debug = "󰃤",
                deps = "󰏗",
                format = "󰉼",
            },
        },
    },
})
```

## Available F# packages (mason registry)

Filter `languages = F#`. In the catalog you pick from these; more exist in the registry and can be
added to the catalog.

| Category | In the catalog | Also in the registry |
| --- | --- | --- |
| LSP | fsautocomplete | — |
| Formatter | fantomas (via the `:LvimLang format` task) | — |
| Linter | — | — |
| DAP | netcoredbg | — |
