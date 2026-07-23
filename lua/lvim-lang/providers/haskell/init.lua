-- lvim-lang.providers.haskell: the Haskell provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Reuses the Rust/Java/Go core: the
-- per-filetype catalog (core.catalog), the LSP fan-out (core.lsp.register_catalog), the lvim-tasks
-- runner (core.runner) and on-demand tooling (core.ensure).
--
-- haskell-language-server (HLS) is the single LSP; the mason `haskell-language-server` package installs
-- a `haskell-language-server-wrapper` that selects the right HLS build for the project's GHC, so the
-- server config launches the wrapper with `--lsp`. HLS formats Haskell natively (its ormolu / fourmolu
-- plugin) and lints inline (its hlint plugin), so the per-filetype efm formatter / linter default to
-- `false`; the catalog still OFFERS fourmolu / ormolu (formatter) and hlint (linter) for users who
-- prefer efm-based tooling. build / run / test go through whichever build tool the project uses —
-- Stack or Cabal, auto-detected per root (providers.haskell.buildtool). Haskell is the user's OWN
-- toolchain (GHCup / mise / asdf), so the requirements surface GHC + the build tool, never install them.
--
---@module "lvim-lang.providers.haskell"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.core.toolchain")
local requirements = require("lvim-lang.core.requirements")
local buildtool = require("lvim-lang.providers.haskell.buildtool")

-- Shared catalog block for both Haskell filetypes (`haskell` and literate `lhaskell`) — the same
-- formatters / linter / debugger apply, each getting its own copy so a user can override one filetype
-- without touching the other.
---@return table
local function ft_block()
    return {
        formatters = {
            -- fourmolu / ormolu through efm (read stdin, emit formatted to stdout). Opt-in: HLS
            -- formats by default via its own ormolu/fourmolu plugin.
            fourmolu = {
                mason = "fourmolu",
                efm = { formatCommand = "fourmolu --stdin-input-file ${INPUT}", formatStdin = true },
            },
            ormolu = {
                mason = "ormolu",
                efm = { formatCommand = "ormolu --stdin-input-file ${INPUT}", formatStdin = true },
            },
        },
        linters = {
            -- hlint through efm (reads the file). Opt-in: HLS surfaces hlint suggestions inline by default.
            hlint = {
                mason = "hlint",
                efm = {
                    lintCommand = "hlint ${INPUT}",
                    lintStdin = false,
                    lintFormats = {
                        "%f:%l:%c-%*[0-9]: %trror: %m",
                        "%f:%l:%c-%*[0-9]: %tarning: %m",
                        "%f:%l:%c: %trror: %m",
                        "%f:%l:%c: %tarning: %m",
                    },
                },
            },
        },
        debuggers = {
            -- haskell-debug-adapter (phoityne): a GHCi-driven DAP server; selecting it installs the
            -- mason package so the adapter binary exists on disk.
            ["haskell-debug-adapter"] = { mason = "haskell-debug-adapter" },
        },
        -- HLS formats + lints natively, so the efm formatter / linter default to false; the
        -- haskell-debug-adapter is the default debugger.
        defaults = { formatter = false, linter = false, debugger = "haskell-debug-adapter" },
    }
end

---@type table
local DEFAULTS = {
    -- Explicit binary paths; when set each wins over every other resolution strategy.
    ghc_path = nil,
    cabal_path = nil,
    stack_path = nil,
    hls_path = nil, -- the haskell-language-server(-wrapper) binary
    fourmolu_path = nil,
    ormolu_path = nil,
    hlint_path = nil,
    -- A shell command whose first output line is the `ghc` binary path (checked after ghc_path,
    -- before the version manager / PATH). Empty by default.
    ghc_lookup_cmd = nil,
    -- Version manager for the toolchain: "ghcup" | "mise" | "asdf" | false (ignore) | function(root, tool).
    -- Honours the active toolchain. Default: try ghcup (`ghcup whereis`), then mise / asdf, then the
    -- GHCup bin dir, then PATH.
    version_manager = nil,

    -- Debugging (haskell-debug-adapter / phoityne). Every field is configurable because phoityne is
    -- sensitive to the project's exact GHCi invocation.
    dap = {
        haskell_debug_adapter_path = nil, -- explicit adapter binary (nil = toolchain / PATH / mason)
        adapter_args = {}, -- extra argv for the adapter process
        -- The GHCi command haskell-debug-adapter starts, per build tool. `TARGET` is phoityne's
        -- placeholder for the loaded main target.
        stack_ghci_cmd = "stack ghci --test --no-load --no-build --main-is TARGET --ghci-options -fprint-evld-with-show",
        cabal_ghci_cmd = "cabal exec -- ghci -fprint-evld-with-show",
        ghci_prompt = "λλλλ> ",
        ghci_initial_prompt = nil, -- nil = reuse ghci_prompt
        ghci_env = nil, -- table<string,string> passed to the GHCi session (nil = none)
        startup_func = "", -- function to call after load (phoityne startupFunc)
        startup_args = "", -- args for startup_func
        stop_on_entry = true,
        log_file = nil, -- nil = stdpath("cache")/lvim-lang-haskell-dap.log
        log_level = "WARNING", -- phoityne log level
    },

    -- LSP server catalog. haskell-language-server is the single Haskell server. HLS is configured
    -- through workspace settings under the `haskell` key (its plugins / formatting provider).
    lsp = {
        servers = {
            ["haskell-language-server"] = {
                mason = "haskell-language-server",
                bin = "haskell-language-server-wrapper", -- the wrapper picks the right HLS for the GHC
                filetypes = { "haskell", "lhaskell" },
                role = "types", -- completion / hover / definition / rename / inlay hints / format
                settings = {
                    haskell = {
                        -- The formatter HLS uses for its own format provider ("ormolu" | "fourmolu" |
                        -- "stylish-haskell" | "brittany" | "floskell" | "none").
                        formattingProvider = "ormolu",
                        checkParents = "CheckOnSave",
                        checkProject = true,
                        plugin = {
                            -- Inline hlint suggestions (so a separate efm linter is not needed).
                            hlint = { globalOn = true },
                        },
                    },
                },
            },
        },
        default = "haskell-language-server",
    },

    -- Per-filetype formatter / linter / debugger catalog + selection (haskell + literate lhaskell).
    ft = {
        haskell = ft_block(),
        lhaskell = ft_block(),
    },

    -- Statusline / picker icons (Nerd Font, single-width, all configurable).
    icons = {
        statusline = "", -- the Haskell marker in the statusline segment (nf-dev-haskell)
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗", -- dependency row
    },
}

--- Health section for :checkhealth lvim-lang: whether the Haskell toolchain (ghc + build tool + HLS)
--- resolves for the current working directory, and at what version.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."

    -- GHC + the build tools: report each with its version, warning when the essential ones are absent.
    local report = {
        { tool = "ghc", level = "warn", hint = "install the Haskell toolchain via GHCup (ghc / cabal / stack)" },
        { tool = "cabal", level = "info", hint = "install Cabal via GHCup (for cabal.project / *.cabal builds)" },
        { tool = "stack", level = "info", hint = "install Stack via GHCup (for stack.yaml builds)" },
    }
    for _, r in ipairs(report) do
        local path, reason = toolchain.resolve("haskell", r.tool, root)
        if path then
            local ver = toolchain.version("haskell", r.tool, root)
            h.ok(("%s: %s%s"):format(r.tool, path, ver and ("  (" .. ver .. ")") or ""))
        elseif r.level == "warn" then
            h.warn(("%s not found — %s"):format(r.tool, reason or r.hint))
        else
            h.info(("%s not found — %s"):format(r.tool, r.hint))
        end
    end

    local hls = toolchain.resolve("haskell", "haskell-language-server", root)
    if hls then
        h.ok(("haskell-language-server: %s"):format(hls))
    else
        h.info("haskell-language-server not found — installed on demand from the mason registry")
    end
end

--- Statusline segment for a root: the Haskell marker + the active run config (if any).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.haskell and config.providers.haskell.icons) or {}
    local parts = { ic.statusline or "" }
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
    name = "haskell",
    filetypes = { "haskell", "lhaskell" },
    root_patterns = { "stack.yaml", "cabal.project", "package.yaml", ".git" },
    statusline = statusline,
    toolchain = require("lvim-lang.providers.haskell.toolchain"),
    commands = require("lvim-lang.providers.haskell.commands"),
    -- lvim-tasks templates (the safe dependency resolve) — also runnable via :LvimLang deps.
    tasks = require("lvim-lang.providers.haskell.deps").templates,
    --- Surfaced at activation + in :checkhealth: GHC and the project's build tool must be present
    --- (HLS needs GHC; build / run / test need the build tool). Haskell is the user's own toolchain.
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
        local reqs = {
            requirements.tool_present(
                "haskell",
                "ghc",
                "GHC (Haskell compiler)",
                "Install the Haskell toolchain via GHCup (https://www.haskell.org/ghcup/) and put `ghc` on "
                    .. "PATH — it provides ghc, cabal, stack and haskell-language-server.",
                root
            ),
        }
        local tool = buildtool.detect(root)
        if tool then
            reqs[#reqs + 1] = requirements.tool_present(
                "haskell",
                tool,
                tool == "stack" and "Stack build tool" or "Cabal build tool",
                "This project uses " .. tool .. " — install it via GHCup and put `" .. tool .. "` on PATH.",
                root
            )
        else
            -- No project build tool detected yet: at least one of Cabal / Stack is needed to build.
            local cabal = toolchain.resolve("haskell", "cabal", root)
            local stack = toolchain.resolve("haskell", "stack", root)
            reqs[#reqs + 1] = {
                label = "Cabal or Stack build tool",
                ok = (cabal or stack) ~= nil,
                detail = (cabal or stack) and ("found: " .. (cabal or stack)) or "neither found",
                hint = "Install Cabal or Stack via GHCup to build / run / test the project.",
                severity = "warn",
            }
        end
        return reqs
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
