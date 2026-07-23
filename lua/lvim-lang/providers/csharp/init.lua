-- lvim-lang.providers.csharp: the C# / .NET provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes, the OmniSharp (default) + roslyn (opt-in) LSP catalog, the per-filetype tool catalog
-- (csharpier / netcoredbg), the dotnet toolchain, requirements, health and statusline. This module then
-- EXTENDS the returned spec with C#'s idiosyncratic parts:
--   * a FUNCTION root matcher (the `*.sln` / `*.csproj` globs vim.fs.root cannot take as literal strings);
--   * bin-keyed toolchain aliases (the server-config modules resolve by the BINARY name — `OmniSharp`,
--     `Microsoft.CodeAnalysis.LanguageServer` — not the catalog key);
--   * the dotnet build/run/test + NuGet + netcoredbg command surface (providers.csharp.commands / .dap / .deps).
--
-- The reusable strategy builders (explicit / lookup / version-manager / mason / PATH) come from core.detect
-- via the factory. OmniSharp / roslyn keep their bespoke server-config modules (servers/omnisharp.lua,
-- servers/roslyn.lua — a real file wins over the generic shim).
--
---@module "lvim-lang.providers.csharp"

local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")

---@type LvimLangSpecData
local DATA = {
    name = "csharp",
    filetypes = { "cs" },
    root_patterns = { ".git" }, -- replaced by the function matcher in the extend (glob markers)

    runtime = {
        bin = "dotnet",
        key = "dotnet",
        lookup_key = "dotnet_lookup_cmd",
        require = true,
        label = ".NET SDK",
        hint = "Install the .NET SDK and put `dotnet` on PATH (or set providers.csharp.bin_paths.dotnet); the C# "
            .. "server, build and test all invoke it.",
    },

    lsp = {
        servers = {
            omnisharp = {
                mason = "omnisharp",
                bin = "OmniSharp",
                filetypes = { "cs" },
                role = "types", -- completion / hover / definition / rename / format
                -- OmniSharp is configured through CLI `key=value` options (not LSP settings); the server
                -- config appends each as a launch argument.
                options = {
                    ["RoslynExtensionsOptions:EnableAnalyzersSupport"] = "true",
                    ["RoslynExtensionsOptions:EnableImportCompletion"] = "true",
                    ["RoslynExtensionsOptions:EnableDecompilationSupport"] = "true",
                    ["FormattingOptions:OrganizeImports"] = "true",
                    ["FormattingOptions:EnableEditorConfigSupport"] = "true",
                    ["Sdk:IncludePrereleases"] = "true",
                },
                settings = {},
            },
            roslyn = {
                mason = "roslyn",
                bin = "Microsoft.CodeAnalysis.LanguageServer",
                filetypes = { "cs" },
                role = "types",
                settings = {},
            },
        },
        default = "omnisharp", -- string | string[]; set to "roslyn" to use the roslyn server instead
    },

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
            -- The LSP formats C# natively → no default efm formatter; the catalog still OFFERS csharpier.
            defaults = { formatter = false, linter = false, debugger = "netcoredbg" },
        },
    },

    icons = {
        statusline = "󰌛", -- the C# marker in the statusline segment
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗", -- NuGet dependency row
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND ─────────────────────────────────────────────────────────────────────────────────────────

--- Whether a directory entry name is a C# project-root marker (a `.sln`/`.csproj` glob, or `.git`).
--- Passed to vim.fs.root as a FUNCTION matcher (globs cannot be literal marker strings).
---@param name string
---@return boolean
local function root_matcher(name)
    return name:match("%.sln$") ~= nil or name:match("%.csproj$") ~= nil or name == ".git"
end
---@diagnostic disable-next-line: assign-type-mismatch
spec.root_patterns = root_matcher

-- The server-config modules resolve the binary by its NAME (not the catalog key): alias them onto the
-- factory's server-key-keyed strategies so toolchain.resolve("csharp", "OmniSharp"/"Microsoft…") works.
local tc = spec.toolchain.tools
tc.OmniSharp = tc.omnisharp
tc["Microsoft.CodeAnalysis.LanguageServer"] = tc.roslyn

spec.commands = require("lvim-lang.providers.csharp.commands")
spec.tasks = require("lvim-lang.providers.csharp.deps").templates

registry.register(spec, defaults)

return spec
