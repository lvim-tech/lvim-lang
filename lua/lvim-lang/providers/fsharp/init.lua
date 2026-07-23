-- lvim-lang.providers.fsharp: the F# / .NET provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes, the fsautocomplete LSP catalog, the per-filetype tool catalog (netcoredbg), the dotnet
-- toolchain, requirements, health and statusline. This module then EXTENDS the returned spec with F#'s
-- idiosyncratic parts:
--   * a FUNCTION root matcher (the `*.sln` / `*.fsproj` globs + literal `paket.dependencies`);
--   * the standalone `fantomas` formatter binary (used by the `:LvimLang format` TASK — Fantomas formats
--     files in place, no stdin mode, so it is not an efm formatter and is resolve-only, not install-union);
--   * the dotnet build/run/test + NuGet + Fantomas + netcoredbg command surface (providers.fsharp.commands
--     / .dap / .deps).
--
-- fsautocomplete formats F# natively (bundled Fantomas) so the efm formatter defaults off. It keeps its
-- bespoke servers/fsautocomplete.lua (a real file wins over the generic shim).
--
---@module "lvim-lang.providers.fsharp"

local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")
local detect = require("lvim-lang.core.detect")

---@type LvimLangSpecData
local DATA = {
    name = "fsharp",
    filetypes = { "fsharp" },
    root_patterns = { ".git" }, -- replaced by the function matcher in the extend (glob markers)

    runtime = {
        bin = "dotnet",
        key = "dotnet",
        lookup_key = "dotnet_lookup_cmd",
        require = true,
        label = ".NET SDK",
        hint = "Install the .NET SDK and put `dotnet` on PATH (or set providers.fsharp.bin_paths.dotnet); the F# "
            .. "server, build and test all invoke it.",
    },

    lsp = {
        servers = {
            fsautocomplete = {
                mason = "fsautocomplete",
                bin = "fsautocomplete",
                filetypes = { "fsharp" },
                role = "types", -- completion / hover / definition / rename / format
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

    ft = {
        fsharp = {
            -- fsautocomplete formats F# natively (bundled Fantomas); standalone Fantomas is the
            -- `:LvimLang format` task (no stdin mode → not efm-compatible), resolved in the extend.
            formatters = {},
            linters = {},
            debuggers = {
                netcoredbg = { mason = "netcoredbg" },
            },
            defaults = { formatter = false, linter = false, debugger = "netcoredbg" },
        },
    },

    icons = {
        statusline = "", -- the F# marker in the statusline segment (nf-dev-fsharp)
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗", -- NuGet dependency row
        format = "󰉼", -- fantomas format task row
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND ─────────────────────────────────────────────────────────────────────────────────────────

--- Whether a directory entry name is an F# project-root marker (a `.sln`/`.fsproj` glob, the literal
--- `paket.dependencies`, or `.git`). Passed to vim.fs.root as a FUNCTION matcher.
---@param name string
---@return boolean
local function root_matcher(name)
    return name:match("%.sln$") ~= nil
        or name:match("%.fsproj$") ~= nil
        or name == "paket.dependencies"
        or name == ".git"
end
---@diagnostic disable-next-line: assign-type-mismatch
spec.root_patterns = root_matcher

-- fantomas: a mason formatter used by the format TASK (not an efm formatter, not install-union) — add its
-- resolution (explicit → mason → PATH) so :LvimLang format resolves it.
spec.toolchain.tools.fantomas = detect.mason_strategies("fsharp", "fantomas")

spec.commands = require("lvim-lang.providers.fsharp.commands")
spec.tasks = require("lvim-lang.providers.fsharp.deps").templates

registry.register(spec, defaults)

return spec
