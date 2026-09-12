# C# / .NET provider

The C# provider owns .NET tooling through `lvim-lang`: **OmniSharp** (LSP, the default) with
**roslyn** as an opt-in alternative, an optional **csharpier** formatter routed through
**efm-langserver**, `dotnet` build / run / test / clean and NuGet dependency commands through
**lvim-tasks**, and **netcoredbg** debugging through **lvim-dap**. Everything is resolved per project
and lazy — nothing is wired until the first C# buffer is opened.

Filetypes: `cs`. Project root: nearest `*.sln` → `*.csproj` → `.git`.

> Root markers are GLOBS (`*.sln` / `*.csproj`). `vim.fs.root` cannot take those as literal marker
> strings, but it DOES accept a FUNCTION matcher, so the provider's `root_patterns` is a predicate
> (`name:match("%.sln$") or name:match("%.csproj$") or name == ".git"`).

## Toolchain

Resolved per project root (nothing is installed here — see the install popup below):

- **`dotnet`** — an explicit `bin_paths.dotnet` → a `dotnet_lookup_cmd` → a **version manager**
  (`mise` / `asdf`, honouring the project's pinned SDK) → `PATH`.
- **`OmniSharp`** / the **roslyn** server / **`csharpier`** / **`netcoredbg`** — an explicit path →
  the mason bin directory (where the installer drops them) → `PATH`.

## LSP: OmniSharp (default) vs roslyn

**OmniSharp is the default** — a plain stdio LSP that works out of the box (`OmniSharp -lsp`).
OmniSharp is configured through CLI `key=value` **options** (not LSP settings); the provider's
`options` block is appended to the launch command.

**roslyn** (`Microsoft.CodeAnalysis.LanguageServer`) is an opt-in alternative — select it with
`providers.csharp.lsp.server = "roslyn"`. It needs a `solution/open` notification after
initialization (roslyn does not open the workspace from `rootUri`); its server-config module sends
that (a `.sln`, else `project/open` for the `.csproj` files). It is **experimental** — prefer
OmniSharp unless you specifically need roslyn.

| Server | Role | Notes |
| --- | --- | --- |
| `omnisharp` (default) | types / hover / definition / rename / format | stdio LSP, `OmniSharp -lsp` |
| `roslyn` | types / hover / definition / rename / format | opt-in; needs `solution/open` (experimental) |

## Per-filetype catalog

The `cs` filetype has its own catalog; you pick a default (or `false` for none). Only the chosen
tools are installed / wired. Formatting is done by the **LSP** natively, so the default formatter is
`false`; the catalog still offers **csharpier** through efm (set `ft.cs.formatter = "csharpier"`).

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `cs` | csharpier | semgrep | netcoredbg | formatter=false, linter=false, debugger=netcoredbg |

## Commands

`:LvimLang <sub> [args]` in a C# buffer:

| Command | Description |
| --- | --- |
| `:LvimLang build [args]` | `dotnet build` |
| `:LvimLang run [args]` | `dotnet run`; applies the active run config |
| `:LvimLang test [args]` | `dotnet test` |
| `:LvimLang test-func` | run the `[Fact]`/`[Theory]`/`[Test]`/`[TestMethod]` under the cursor (`--filter FullyQualifiedName~Class.Method`) |
| `:LvimLang test-file` | `dotnet test` the current buffer's test class |
| `:LvimLang clean [args]` | `dotnet clean` |
| `:LvimLang add <package[@version]> [args]` | `dotnet add package` |
| `:LvimLang remove <package>` | `dotnet remove package` |
| `:LvimLang restore [args]` | `dotnet restore` |
| `:LvimLang deps <restore\|list>` | NuGet dependency commands (`dotnet restore` / `dotnet list package`) |
| `:LvimLang debug` | start / continue a netcoredbg session |
| `:LvimLang config` | pick the active run configuration (`.lvim/lang/run.lua`) |

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
        project = "src/Api/Api.csproj", -- --project
        configuration = "Debug", -- -c Debug
        dotnet_flags = { "--no-restore" }, -- extra `dotnet run` flags
        args = { "--urls", "http://localhost:5000" }, -- program arguments (after --)
        env = { ASPNETCORE_ENVIRONMENT = "Development" },
    },
    { name = "cli", project = "src/Cli/Cli.csproj" },
}
```

## Configuration

The complete default `providers.csharp` block (every value overridable via `setup()`):

```lua
require("lvim-lang").setup({
    providers = {
        csharp = {
            -- Toolchain (explicit paths win over resolution).
            bin_paths = { -- explicit binaries by toolchain tool key (win over every other strategy)
                dotnet = nil,
                omnisharp = nil,
                roslyn = nil,
                csharpier = nil,
                netcoredbg = nil,
            },
            dotnet_lookup_cmd = nil, -- shell command whose first line is the `dotnet` path
            version_manager = nil, -- "mise" | "asdf" | false | function(root); default: mise→asdf→PATH

            -- LSP server catalog + selection.
            lsp = {
                servers = {
                    omnisharp = {
                        mason = "omnisharp",
                        bin = "OmniSharp",
                        filetypes = { "cs" },
                        role = "types",
                        -- OmniSharp is configured via CLI key=value options (appended to the command).
                        options = {
                            ["RoslynExtensionsOptions:EnableAnalyzersSupport"] = "true",
                            ["RoslynExtensionsOptions:EnableImportCompletion"] = "true",
                            ["RoslynExtensionsOptions:EnableDecompilationSupport"] = "true",
                            ["FormattingOptions:OrganizeImports"] = "true",
                            ["FormattingOptions:EnableEditorConfigSupport"] = "true",
                            ["Sdk:IncludePrereleases"] = "true",
                        },
                        settings = {}, -- raw LSP settings, forwarded when non-empty
                    },
                    roslyn = {
                        mason = "roslyn",
                        bin = "Microsoft.CodeAnalysis.LanguageServer",
                        filetypes = { "cs" },
                        role = "types",
                        settings = {},
                    },
                },
                default = "omnisharp", -- string | string[]; set to "roslyn" to use the roslyn server
            },

            -- Per-filetype formatter / linter / debugger catalog + selection.
            ft = {
                cs = {
                    formatters = {
                        csharpier = {
                            mason = "csharpier",
                            efm = { formatCommand = "csharpier --write-stdout", formatStdin = true },
                        },
                    },
                    linters = {},
                    debuggers = {
                        netcoredbg = { mason = "netcoredbg" },
                    },
                    -- Only the chosen tools install / wire (false = none). The LSP formats C# natively.
                    defaults = { formatter = false, linter = false, debugger = "netcoredbg" },
                },
            },

            -- Statusline / picker icons (Nerd Font).
            icons = {
                statusline = "󰌛",
                test = "󰙨",
                build = "󰜫",
                run = "󰐊",
                debug = "󰃤",
                deps = "󰏗",
            },
        },
    },
})
```

## Available C# packages (mason registry)

Filter `languages = C#`. In the catalog you pick from these; more exist in the registry and can be
added to the catalog.

| Category | In the catalog | Also in the registry |
| --- | --- | --- |
| LSP | omnisharp, roslyn | — |
| Formatter | csharpier | — |
| Linter | — | — |
| DAP | netcoredbg | — |
