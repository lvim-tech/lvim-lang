-- lvim-lang.providers.ocaml.dap: OCaml debugging through lvim-dap, backed by earlybird.
-- earlybird (mason package `ocamlearlybird`, binary `ocamlearlybird`) is the OCaml debug adapter. It
-- debugs BYTECODE executables (dune's `.bc` targets — build with `dune build` so the `.bc` exists),
-- NOT native-code binaries, so the launch config's `program` points at a `_build/.../*.bc`. The
-- adapter is an `executable` DAP server (`ocamlearlybird debug`, stdio) handed to lvim-ls via the
-- ocaml-lsp server config's `dap` field (auto-registered with lvim-dap on attach). `:LvimLang debug`
-- continues / starts a session, prompting for the bytecode under the build dir.
--
---@module "lvim-lang.providers.ocaml.dap"

local M = {}

--- The ocaml config block.
---@return table
local function opts()
    return require("lvim-lang.config").providers.ocaml or {}
end

--- The dune project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "dune-project", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Resolve the earlybird binary: an explicit config path → PATH (the mason / opam install).
---@return string
local function earlybird_bin()
    local o = opts()
    if o.earlybird_path and vim.fn.executable(o.earlybird_path) == 1 then
        return o.earlybird_path
    end
    local p = vim.fn.exepath("ocamlearlybird")
    return p ~= "" and p or "ocamlearlybird"
end

--- Prompt for the bytecode executable to debug, defaulting under the dune build dir of the current
--- buffer's root (earlybird debugs `.bc` bytecode, which dune drops under `_build/default/`).
---@return string
local function pick_program()
    local root = root_of(vim.api.nvim_get_current_buf())
    local base = root .. "/" .. (opts().build_dir or "_build") .. "/default/"
    return vim.fn.input("Path to bytecode (.bc): ", base, "file")
end

--- The static `dap` field for the ocaml-lsp server config (adapter + base launch configuration).
---@return table
function M.spec()
    return {
        adapters = {
            -- earlybird is a stdio DAP server started with the `debug` subcommand.
            ocamlearlybird = {
                type = "executable",
                command = earlybird_bin(),
                args = { "debug" },
            },
        },
        configurations = {
            ocaml = {
                {
                    type = "ocamlearlybird",
                    request = "launch",
                    name = "Debug bytecode (earlybird)",
                    program = pick_program,
                    cwd = "${workspaceFolder}",
                    stopOnEntry = false,
                    -- earlybird checkpoints every `yieldSteps` instructions for reverse-execution.
                    yieldSteps = 4096,
                },
            },
        },
    }
end

--- `:LvimLang debug` — continue / start a debug session (lvim-dap picks a configuration).
---@param _args string[]
---@param _ctx table
---@return nil
function M.debug(_args, _ctx)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok then
        vim.notify("lvim-lang: lvim-dap not available", vim.log.levels.WARN, { title = "lvim-lang" })
        return
    end
    dap.continue()
end

return M
