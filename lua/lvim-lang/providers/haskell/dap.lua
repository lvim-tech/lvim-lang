-- lvim-lang.providers.haskell.dap: Haskell debugging through lvim-dap, backed by haskell-debug-adapter.
-- haskell-debug-adapter (phoityne) is a GHCi-driven DAP server: it launches a GHCi session for the
-- project and steps the loaded module. It runs as an `executable` adapter (stdio), and its launch
-- configuration must carry the GHCi command to start — which DIFFERS by build tool, so the base config
-- is built per project: Stack → `stack ghci`, Cabal → `cabal repl`, both with `-fprint-evld-with-show`
-- (so evaluated bindings print). Every field (the ghci command, prompt, log level) is configurable
-- under `providers.haskell.dap`, because phoityne is sensitive to the project's exact GHCi invocation.
-- The static adapter + base config are handed to lvim-ls via the HLS server config's `dap` field
-- (auto-registered with lvim-dap on attach). `:LvimLang debug` continues / starts a session, loading
-- the current file (`startup`).
--
-- NB: phoityne/haskell-debug-adapter is the fragile corner of the Haskell toolchain — the default
-- GHCi command works for a plain `stack`/`cabal` layout but a project with a bespoke test/exe target
-- may need `providers.haskell.dap.stack_ghci_cmd` / `cabal_ghci_cmd` tuned. See docs/providers/haskell.md.
--
---@module "lvim-lang.providers.haskell.dap"

local buildtool = require("lvim-lang.providers.haskell.buildtool")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The haskell config block.
---@return table
local function opts()
    return require("lvim-lang.config").providers.haskell or {}
end

--- The dap sub-block (log level, prompt, per-tool GHCi commands, explicit adapter path).
---@return table
local function dap_opts()
    return opts().dap or {}
end

--- Resolve the haskell-debug-adapter binary: an explicit config path → the toolchain resolution →
--- PATH (the mason install).
---@param root string
---@return string
local function hda_bin(root)
    local o = dap_opts()
    if o.haskell_debug_adapter_path and vim.fn.executable(o.haskell_debug_adapter_path) == 1 then
        return o.haskell_debug_adapter_path
    end
    local resolved = require("lvim-lang.core.toolchain").resolve("haskell", "haskell-debug-adapter", root)
    if resolved and resolved ~= "" then
        return resolved
    end
    local p = vim.fn.exepath("haskell-debug-adapter")
    return p ~= "" and p or "haskell-debug-adapter"
end

--- The GHCi command haskell-debug-adapter starts for a root, chosen by the build tool (Stack →
--- `stack_ghci_cmd`, Cabal → `cabal_ghci_cmd`; a `cabal`/unknown project uses the Cabal command).
---@param root string
---@return string
local function ghci_cmd(root)
    local o = dap_opts()
    if buildtool.detect(root) == "stack" then
        return o.stack_ghci_cmd
            or "stack ghci --test --no-load --no-build --main-is TARGET --ghci-options -fprint-evld-with-show"
    end
    return o.cabal_ghci_cmd or "cabal exec -- ghci -fprint-evld-with-show"
end

--- The haskell-debug-adapter executable adapter (stdio). Resolves the binary per root at launch.
---@return fun(callback: fun(adapter: table), config: table)
local function adapter()
    return function(callback, config)
        local root = (config and config.workspace) or vim.uv.cwd() or "."
        callback({ type = "executable", command = hda_bin(root), args = dap_opts().adapter_args or {} })
    end
end

--- The static `dap` field for the HLS server config (adapter + a base launch configuration). The
--- launch config loads the current file (`startup`) into the tool-appropriate GHCi session.
---@return table
function M.spec()
    local o = dap_opts()
    return {
        adapters = { haskell = adapter() },
        configurations = {
            haskell = {
                {
                    type = "haskell",
                    request = "launch",
                    name = "Debug (haskell-debug-adapter)",
                    workspace = "${workspaceFolder}",
                    startup = "${file}",
                    startupFunc = o.startup_func or "",
                    startupArgs = o.startup_args or "",
                    stopOnEntry = o.stop_on_entry ~= false, -- default true (phoityne convention)
                    -- The GHCi command is resolved per project at launch (Stack vs Cabal).
                    ghciCmd = function()
                        return ghci_cmd(require("lvim-lang.providers.haskell.tasks").root())
                    end,
                    ghciPrompt = o.ghci_prompt or "λλλλ> ",
                    ghciInitialPrompt = o.ghci_initial_prompt or o.ghci_prompt or "λλλλ> ",
                    ghciEnv = o.ghci_env or vim.empty_dict(),
                    logFile = o.log_file or (vim.fn.stdpath("cache") .. "/lvim-lang-haskell-dap.log"),
                    logLevel = o.log_level or "WARNING",
                },
            },
        },
    }
end

--- `:LvimLang debug` — continue / start a debug session (lvim-dap picks the configuration).
---@param _args string[]
---@param _ctx table
---@return nil
function M.debug(_args, _ctx)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok then
        vim.notify("lvim-lang: lvim-dap not available", vim.log.levels.WARN, TITLE)
        return
    end
    dap.continue()
end

return M
