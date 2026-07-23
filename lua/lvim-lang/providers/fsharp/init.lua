-- lvim-lang.providers.fsharp: the F# / .NET provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Wires the toolchain (dotnet / the
-- fsautocomplete language server / fantomas / netcoredbg resolution), a health section, a statusline
-- segment, the LSP catalog, the per-filetype formatter/linter/debugger catalog, `dotnet`
-- build/run/test tasks, NuGet dependency commands and netcoredbg debugging.
--
-- LSP: fsautocomplete (FsAutoComplete) is the F# language server — a plain stdio LSP that works out
-- of the box (mason `fsautocomplete`, binary `fsautocomplete`). It is configured through LSP
-- `settings` under the `FSharp` namespace, and formats F# NATIVELY through its bundled Fantomas — so
-- the default efm formatter is `false` (like C#'s LSP-native formatting). The provider also OFFERS a
-- standalone `:LvimLang format` task that runs Fantomas on the file/project directly.
--
-- Root markers are GLOBS (`*.fsproj` / `*.sln`) plus the literal `paket.dependencies`, which
-- vim.fs.root cannot take as literal glob strings — but it DOES accept a FUNCTION matcher, so
-- `root_patterns` is a predicate (with a `.git` fallback); the registry passes it straight to
-- vim.fs.root.
--
---@module "lvim-lang.providers.fsharp"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.providers.fsharp.toolchain")
local core_toolchain = require("lvim-lang.core.toolchain")
local requirements = require("lvim-lang.core.requirements")

-- Per-language defaults, merged into config.providers.fsharp at registration (users override via
-- setup({ providers = { fsharp = { … } } })).
---@type table
local DEFAULTS = {
    -- Explicit binary paths; when set each wins over every other resolution strategy.
    dotnet_path = nil,
    fsautocomplete_path = nil,
    fantomas_path = nil,
    netcoredbg_path = nil,
    -- A shell command whose first output line is the `dotnet` binary path (checked after dotnet_path,
    -- before the version manager / PATH). Empty by default.
    dotnet_lookup_cmd = nil,
    -- Version manager for the `dotnet` SDK: "mise" | "asdf" | false (ignore) | function(root). Honours
    -- the project's pinned SDK (global.json / .tool-versions). Default: try mise then asdf, else PATH.
    version_manager = nil,

    -- LSP server catalog. fsautocomplete is the only F# server (a plain stdio LSP). `default` may be a
    -- STRING or a LIST (several LSP clients attach to the same buffer).
    lsp = {
        servers = {
            fsautocomplete = {
                mason = "fsautocomplete",
                bin = "fsautocomplete",
                filetypes = { "fsharp" },
                role = "types", -- completion / hover / definition / rename / format
                -- FsAutoComplete is configured through LSP settings under the `FSharp` namespace,
                -- forwarded as-is when non-empty.
                settings = {
                    FSharp = {
                        -- Roslyn-style analyzers + tooltips.
                        keywordsAutocomplete = true,
                        ExternalAutocomplete = false,
                        -- Inlay hints (type + parameter names).
                        inlayHints = { enabled = true, typeAnnotations = true, parameterNames = true },
                        -- Show the signature line above a symbol in the CodeLens row.
                        lineLens = { enabled = "replaceCodeLens", prefix = "// " },
                        -- Run the built-in analyzers.
                        enableAnalyzers = true,
                        -- Use the in-process, adaptive server pipeline.
                        fsac = { conserveMemory = false },
                    },
                },
            },
        },
        default = "fsautocomplete", -- string | string[]
    },

    -- Per-FILETYPE catalog: formatters / linters / debuggers available for `fsharp`, each with a
    -- default configuration, plus which one is the `default` (or false = none). Only the CHOSEN tools
    -- are installed (their mason package is contributed to the installer) and wired (through
    -- efm-langserver). Every entry is fully overridable via
    -- setup({ providers = { fsharp = { ft = { fsharp = { … } } } } }).
    ft = {
        fsharp = {
            -- No efm formatter: FsAutoComplete formats F# natively (bundled Fantomas), so a separate
            -- efm formatter is redundant. Standalone Fantomas is still offered as the `:LvimLang
            -- format` TASK (Fantomas formats files in place — it has no stdin mode — so it does not fit
            -- efm's stdin contract; a task is the clean mechanism).
            formatters = {},
            linters = {},
            debuggers = {
                netcoredbg = { mason = "netcoredbg" },
            },
            defaults = { formatter = false, linter = false, debugger = "netcoredbg" },
        },
    },

    -- Nerd Font icons used in the F# provider's pickers / statusline (all configurable).
    icons = {
        statusline = "", -- the F# marker in the statusline segment (nf-dev-fsharp)
        test = "󰙨", -- test runner / result row
        build = "󰜫", -- build task row
        run = "󰐊", -- run task row
        debug = "󰃤", -- debug session row
        deps = "󰏗", -- NuGet dependency row
        format = "󰉼", -- fantomas format task row
    },
}

--- Health section for :checkhealth lvim-lang: report whether the .NET toolchain resolves for the
--- current working directory, and at what version.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."
    for _, tool in ipairs({ "dotnet", "fsautocomplete", "netcoredbg" }) do
        local path, reason = core_toolchain.resolve("fsharp", tool, root)
        if path then
            local ver = core_toolchain.version("fsharp", tool, root)
            h.ok(("%s: %s%s"):format(tool, path, ver and ("  (" .. ver .. ")") or ""))
        elseif tool == "dotnet" then
            h.warn(("dotnet not found — %s"):format(reason or "install the .NET SDK"))
        else
            h.info(("%s not found — installed on demand from the mason registry"):format(tool))
        end
    end
end

--- Statusline segment for a root: the F# marker + the active run config (if any).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.fsharp and config.providers.fsharp.icons) or {}
    local parts = { ic.statusline or "" }
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

--- Whether a directory entry name is an F# project-root marker (a `.sln`/`.fsproj` glob, the literal
--- `paket.dependencies`, or `.git`). Passed to vim.fs.root as a FUNCTION matcher (globs cannot be
--- literal marker strings).
---@param name string
---@return boolean
local function root_matcher(name)
    return name:match("%.sln$") ~= nil
        or name:match("%.fsproj$") ~= nil
        or name == "paket.dependencies"
        or name == ".git"
end

---@type LvimLangProvider
local spec = {
    name = "fsharp",
    filetypes = { "fsharp" },
    -- vim.fs.root accepts a FUNCTION matcher, but the registry field is typed string[] (it cannot be
    -- widened here without touching the shared spec); the registry passes this straight through.
    ---@diagnostic disable-next-line: assign-type-mismatch
    root_patterns = root_matcher,
    statusline = statusline,
    toolchain = toolchain,
    commands = require("lvim-lang.providers.fsharp.commands"),
    -- lvim-tasks templates (arg-less dotnet dependency subcommands) — also via :LvimLang deps.
    tasks = require("lvim-lang.providers.fsharp.deps").templates,
    --- Surfaced at activation + in :checkhealth: the .NET SDK must be present (server, build, test).
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
        return {
            requirements.tool_present(
                "fsharp",
                "dotnet",
                ".NET SDK",
                "Install the .NET SDK and put `dotnet` on PATH (or set providers.fsharp.dotnet_path); the F# "
                    .. "server, build and test all invoke it.",
                root
            ),
        }
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
