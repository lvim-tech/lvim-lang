-- lvim-lang.providers.csharp: the C# / .NET provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Wires the toolchain (dotnet / the
-- language server / csharpier / netcoredbg resolution), a health section, a statusline segment, the
-- LSP catalog, the per-filetype formatter/linter/debugger catalog, `dotnet` build/run/test tasks,
-- NuGet dependency commands and netcoredbg debugging.
--
-- LSP: OmniSharp is the DEFAULT — a plain stdio LSP that works out of the box (mason `omnisharp`,
-- binary `OmniSharp`, launched `OmniSharp -lsp`). The roslyn server (Microsoft.CodeAnalysis.
-- LanguageServer) is included in the catalog as an OPT-IN alternative: it needs a `solution/open`
-- notification after init, which its server-config module (servers/roslyn.lua) sends — select it via
-- `providers.csharp.lsp.server = "roslyn"`. The catalog below is DERIVED from the mason registry
-- (languages = C#); the user picks a default per filetype (or `false` = none) and overrides any
-- setting. The default efm formatter is `false` — the LSP formats C# natively; the catalog still
-- OFFERS csharpier for users who prefer efm-based formatting.
--
-- Root markers are GLOBS (`*.sln` / `*.csproj`), which vim.fs.root cannot take as literal strings —
-- but it DOES accept a FUNCTION matcher, so `root_patterns` is a predicate (with a `.git` fallback);
-- the registry passes it straight to vim.fs.root.
--
---@module "lvim-lang.providers.csharp"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.providers.csharp.toolchain")
local core_toolchain = require("lvim-lang.core.toolchain")
local requirements = require("lvim-lang.core.requirements")

-- Per-language defaults, merged into config.providers.csharp at registration (users override via
-- setup({ providers = { csharp = { … } } })).
---@type table
local DEFAULTS = {
    -- Explicit binary paths; when set each wins over every other resolution strategy.
    dotnet_path = nil,
    omnisharp_path = nil,
    roslyn_path = nil,
    csharpier_path = nil,
    netcoredbg_path = nil,
    -- A shell command whose first output line is the `dotnet` binary path (checked after dotnet_path,
    -- before the version manager / PATH). Empty by default.
    dotnet_lookup_cmd = nil,
    -- Version manager for the `dotnet` SDK: "mise" | "asdf" | false (ignore) | function(root). Honours
    -- the project's pinned SDK (global.json / .tool-versions). Default: try mise then asdf, else PATH.
    version_manager = nil,

    -- LSP server catalog. OmniSharp is the default (a plain stdio LSP). roslyn is an opt-in
    -- alternative (needs solution/open handling; see servers/roslyn.lua). `default` may be a STRING
    -- or a LIST (several LSP clients attach to the same buffer).
    lsp = {
        servers = {
            omnisharp = {
                mason = "omnisharp",
                bin = "OmniSharp",
                filetypes = { "cs" },
                role = "types", -- completion / hover / definition / rename / format
                -- OmniSharp is configured through CLI `key=value` options (not LSP settings). The
                -- server config appends each as a launch argument.
                options = {
                    ["RoslynExtensionsOptions:EnableAnalyzersSupport"] = "true",
                    ["RoslynExtensionsOptions:EnableImportCompletion"] = "true",
                    ["RoslynExtensionsOptions:EnableDecompilationSupport"] = "true",
                    ["FormattingOptions:OrganizeImports"] = "true",
                    ["FormattingOptions:EnableEditorConfigSupport"] = "true",
                    ["Sdk:IncludePrereleases"] = "true",
                },
                -- Raw LSP settings, forwarded as-is when non-empty (most config goes via `options`).
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

    -- Per-FILETYPE catalog: formatters / linters / debuggers available for `cs`, each with a default
    -- configuration, plus which one is the `default` (or false = none). Only the CHOSEN tools are
    -- installed (their mason package is contributed to the installer) and wired (through
    -- efm-langserver). Every entry is fully overridable via
    -- setup({ providers = { csharp = { ft = { cs = { formatter = "csharpier" } } } } }).
    ft = {
        cs = {
            formatters = {
                -- csharpier over efm (reads stdin, writes to stdout). Opt-in: the LSP formats by default.
                csharpier = {
                    mason = "csharpier",
                    efm = { formatCommand = "csharpier --write-stdout", formatStdin = true },
                },
            },
            linters = {},
            debuggers = {
                netcoredbg = { mason = "netcoredbg" },
            },
            -- No default efm formatter: the LSP formats C# natively, so a separate formatter is
            -- redundant. The catalog still OFFERS csharpier (set ft.cs.formatter = "csharpier").
            defaults = { formatter = false, linter = false, debugger = "netcoredbg" },
        },
    },

    -- Nerd Font icons used in the C# provider's pickers / statusline (all configurable).
    icons = {
        statusline = "󰌛", -- the C# marker in the statusline segment
        test = "󰙨", -- test runner / result row
        build = "󰜫", -- build task row
        run = "󰐊", -- run task row
        debug = "󰃤", -- debug session row
        deps = "󰏗", -- NuGet dependency row
    },
}

--- Health section for :checkhealth lvim-lang: report whether the .NET toolchain resolves for the
--- current working directory, and at what version.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."
    -- Report the CHOSEN language server binary (OmniSharp by default; the roslyn server otherwise).
    local lsp = (config.providers.csharp and config.providers.csharp.lsp) or {}
    local server = lsp.server or lsp.default or "omnisharp"
    local server_bin = server == "roslyn" and "Microsoft.CodeAnalysis.LanguageServer" or "OmniSharp"
    for _, tool in ipairs({ "dotnet", server_bin, "netcoredbg" }) do
        local path, reason = core_toolchain.resolve("csharp", tool, root)
        if path then
            local ver = core_toolchain.version("csharp", tool, root)
            h.ok(("%s: %s%s"):format(tool, path, ver and ("  (" .. ver .. ")") or ""))
        elseif tool == "dotnet" then
            h.warn(("dotnet not found — %s"):format(reason or "install the .NET SDK"))
        else
            h.info(("%s not found — installed on demand from the mason registry"):format(tool))
        end
    end
end

--- Statusline segment for a root: the C# marker + the active run config (if any).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.csharp and config.providers.csharp.icons) or {}
    local parts = { ic.statusline or "" }
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

--- Whether a directory entry name is a C# project-root marker (a `.sln`/`.csproj` glob, or `.git`).
--- Passed to vim.fs.root as a FUNCTION matcher (globs cannot be literal marker strings).
---@param name string
---@return boolean
local function root_matcher(name)
    return name:match("%.sln$") ~= nil or name:match("%.csproj$") ~= nil or name == ".git"
end

---@type LvimLangProvider
local spec = {
    name = "csharp",
    filetypes = { "cs" },
    -- vim.fs.root accepts a FUNCTION matcher, but the registry field is typed string[] (it cannot be
    -- widened here without touching the shared spec); the registry passes this straight through.
    ---@diagnostic disable-next-line: assign-type-mismatch
    root_patterns = root_matcher,
    statusline = statusline,
    toolchain = toolchain,
    commands = require("lvim-lang.providers.csharp.commands"),
    -- lvim-tasks templates (arg-less dotnet dependency subcommands) — also via :LvimLang deps.
    tasks = require("lvim-lang.providers.csharp.deps").templates,
    --- Surfaced at activation + in :checkhealth: the .NET SDK must be present (server, build, test).
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
        return {
            requirements.tool_present(
                "csharp",
                "dotnet",
                ".NET SDK",
                "Install the .NET SDK and put `dotnet` on PATH (or set providers.csharp.dotnet_path); the C# "
                    .. "server, build and test all invoke it.",
                root
            ),
        }
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
