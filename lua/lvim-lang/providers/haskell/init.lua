-- lvim-lang.providers.haskell: the Haskell provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes (haskell + literate lhaskell), the HLS catalog, the per-filetype tool catalog (fourmolu
-- / ormolu / hlint / haskell-debug-adapter), the ghc requirement, health and statusline. This module then
-- EXTENDS the returned spec with Haskell's idiosyncratic toolchain resolution + conditional requirements:
--   * ghc / cabal / stack / HLS resolved through GHCup (`ghcup whereis <component>`) → mise/asdf →
--     the GHCup bin dir → PATH — the wrapper HLS binary picks the right build for the project's GHC;
--   * a CONDITIONAL build-tool requirement (Stack or Cabal, auto-detected per root — providers.haskell.buildtool);
--   * the Stack/Cabal build/run/test + phoityne debugging + dependency command surface.
--
-- HLS keeps its bespoke servers/haskell-language-server.lua (a real file wins over the generic shim).
--
---@module "lvim-lang.providers.haskell"

local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")
local detect = require("lvim-lang.core.detect")
local requirements = require("lvim-lang.core.requirements")
local core_toolchain = require("lvim-lang.core.toolchain")
local buildtool = require("lvim-lang.providers.haskell.buildtool")

-- Shared catalog block for both Haskell filetypes (`haskell` and literate `lhaskell`) — the same
-- formatters / linter / debugger, each getting its own copy so a user can override one filetype alone.
---@return table
local function ft_block()
    return {
        formatters = {
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
            ["haskell-debug-adapter"] = { mason = "haskell-debug-adapter" },
        },
        -- HLS formats + lints natively → efm formatter / linter default false; the debug adapter is default.
        defaults = { formatter = false, linter = false, debugger = "haskell-debug-adapter" },
    }
end

---@type LvimLangSpecData
local DATA = {
    name = "haskell",
    filetypes = { "haskell", "lhaskell" },
    root_patterns = { "stack.yaml", "cabal.project", "package.yaml", ".git" },

    runtimes = {
        {
            bin = "ghc",
            key = "ghc",
            lookup_key = "ghc_lookup_cmd",
            require = true,
            label = "GHC (Haskell compiler)",
            hint = "Install the Haskell toolchain via GHCup (https://www.haskell.org/ghcup/) and put `ghc` on "
                .. "PATH — it provides ghc, cabal, stack and haskell-language-server.",
        },
        { bin = "cabal", key = "cabal" },
        { bin = "stack", key = "stack" },
    },

    lsp = {
        servers = {
            ["haskell-language-server"] = {
                mason = "haskell-language-server",
                bin = "haskell-language-server-wrapper", -- the wrapper picks the right HLS for the GHC
                filetypes = { "haskell", "lhaskell" },
                role = "types", -- completion / hover / definition / rename / inlay hints / format
                settings = {
                    haskell = {
                        formattingProvider = "ormolu",
                        checkParents = "CheckOnSave",
                        checkProject = true,
                        plugin = {
                            hlint = { globalOn = true },
                        },
                    },
                },
            },
        },
        default = "haskell-language-server",
    },

    ft = {
        haskell = ft_block(),
        lhaskell = ft_block(),
    },

    icons = {
        statusline = "", -- the Haskell marker in the statusline segment (nf-dev-haskell)
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗",
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND: GHCup toolchain resolution ──────────────────────────────────────────────────────────────

-- The GHCup component name for each toolchain tool (`ghcup whereis <component>`).
---@type table<string, string>
local GHCUP_COMPONENT = { ghc = "ghc", cabal = "cabal", stack = "stack", ["haskell-language-server"] = "hls" }

--- Resolve `tool` through the version manager: `ghcup whereis <component>` (active GHCup set) then
--- `mise`/`asdf which`. `version_manager` may name one, be false, or be a function(root, tool).
---@param tool string
---@return fun(root: string): string|nil
local function via_vm(tool)
    return function(root)
        local vm = (require("lvim-lang.config").providers.haskell or {}).version_manager
        if vm == false then
            return nil
        end
        if type(vm) == "function" then
            return vm(root, tool)
        end
        local managers = type(vm) == "string" and { vm } or { "ghcup", "mise", "asdf" }
        for _, mgr in ipairs(managers) do
            if vim.fn.executable(mgr) == 1 then
                local argv
                if mgr == "ghcup" then
                    local component = GHCUP_COMPONENT[tool]
                    argv = component and { mgr, "whereis", component } or nil
                else
                    argv = { mgr, "which", tool }
                end
                if argv then
                    local out = vim.system(argv, { cwd = root, text = true }):wait()
                    if out.code == 0 then
                        local path = vim.trim(out.stdout or "")
                        if path ~= "" and vim.fn.executable(path) == 1 then
                            return path
                        end
                    end
                end
            end
        end
        return nil
    end
end

--- The on-disk `bin` inside the GHCup bin dir (`$GHCUP_BIN` or `~/.ghcup/bin`), if executable.
---@param bin string
---@return fun(): string|nil
local function ghcup(bin)
    return function()
        local dir = vim.env.GHCUP_BIN
        if not dir or dir == "" then
            dir = vim.fs.joinpath(vim.env.HOME or vim.fn.expand("~"), ".ghcup", "bin")
        end
        local path = vim.fs.joinpath(dir, bin)
        return vim.fn.executable(path) == 1 and path or nil
    end
end

local tc = spec.toolchain.tools
tc.ghc = {
    { kind = "path", value = detect.explicit("haskell", "ghc") },
    { kind = "path", value = detect.lookup("haskell", "ghc_lookup_cmd") },
    { kind = "path", value = via_vm("ghc") },
    { kind = "path", value = ghcup("ghc") },
    { kind = "which", value = "ghc" },
}
tc.cabal = {
    { kind = "path", value = detect.explicit("haskell", "cabal") },
    { kind = "path", value = via_vm("cabal") },
    { kind = "path", value = ghcup("cabal") },
    { kind = "which", value = "cabal" },
}
tc.stack = {
    { kind = "path", value = detect.explicit("haskell", "stack") },
    { kind = "path", value = via_vm("stack") },
    { kind = "path", value = ghcup("stack") },
    { kind = "which", value = "stack" },
}
tc["haskell-language-server"] = {
    { kind = "path", value = detect.explicit("haskell", "haskell-language-server") },
    { kind = "path", value = via_vm("haskell-language-server") },
    { kind = "path", value = ghcup("haskell-language-server-wrapper") },
    { kind = "path", value = detect.in_mason("haskell-language-server-wrapper") },
    { kind = "which", value = "haskell-language-server-wrapper" },
    { kind = "which", value = "haskell-language-server" },
}

-- Requirements: the factory surfaces ghc; add the CONDITIONAL build-tool requirement (detected per root).
local base_reqs = spec.requirements
spec.requirements = function(root)
    local reqs = base_reqs and base_reqs(root) or {}
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
        local cabal = core_toolchain.resolve("haskell", "cabal", root)
        local stack = core_toolchain.resolve("haskell", "stack", root)
        reqs[#reqs + 1] = {
            label = "Cabal or Stack build tool",
            ok = (cabal or stack) ~= nil,
            detail = (cabal or stack) and ("found: " .. (cabal or stack)) or "neither found",
            hint = "Install Cabal or Stack via GHCup to build / run / test the project.",
            severity = "warn",
        }
    end
    return reqs
end

-- Debugging (haskell-debug-adapter / phoityne) — every field configurable (phoityne is sensitive to the
-- project's exact GHCi invocation).
defaults.dap = {
    haskell_debug_adapter_path = nil,
    adapter_args = {},
    stack_ghci_cmd = "stack ghci --test --no-load --no-build --main-is TARGET --ghci-options -fprint-evld-with-show",
    cabal_ghci_cmd = "cabal exec -- ghci -fprint-evld-with-show",
    ghci_prompt = "λλλλ> ",
    ghci_initial_prompt = nil,
    ghci_env = nil,
    startup_func = "",
    startup_args = "",
    stop_on_entry = true,
    log_file = nil,
    log_level = "WARNING",
}

spec.commands = require("lvim-lang.providers.haskell.commands")
spec.tasks = require("lvim-lang.providers.haskell.deps").templates

registry.register(spec, defaults)

return spec
