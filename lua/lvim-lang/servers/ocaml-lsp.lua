-- lvim-lang.servers.ocaml-lsp: the lvim-ls server-config module for ocaml-lsp (binary `ocamllsp`).
-- Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the OCaml provider's LSP
-- catalog registers through core.lsp (register_catalog fans the chosen servers out). lvim-lang does
-- NOT own the LSP lifecycle — this module only DESCRIBES the server; the canonical lvim-ls bootstrap
-- starts and manages the client.
--
-- ocaml-lsp is configured through initializationOptions (not workspace settings): the `init_options`
-- catalog entry (codelens / extendedHover / inlay hints / dune diagnostics). `lsp.config` is a
-- FUNCTION (a seam lvim-ls supports): evaluated fresh per project root so the `ocamllsp` binary is
-- resolved per root through core.toolchain (an explicit path / the active opam switch / the mason bin
-- / PATH — a project-local `_opam/` switch wins). The `efm` field is per-filetype
-- (core.catalog.efm_groups): a chosen ocamlformat lands on the `.ml` / `.mli` filetypes only.
--
---@module "lvim-lang.servers.ocaml-lsp"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local ocaml_dap = require("lvim-lang.providers.ocaml.dap")

--- The OCaml provider's config block.
---@return table
local function opts()
    return config.providers.ocaml or {}
end

--- The ocaml-lsp server catalog entry (init_options / settings), from config.providers.ocaml.lsp.
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers["ocaml-lsp"]) or {}
end

--- Resolve the project root for the current buffer using dune's root markers.
---@return string
local function current_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "dune-project", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The LSP client_capabilities fragment: lvim-cmp's when present, else the Neovim defaults.
---@return table
local function capabilities()
    local ok, cmp = pcall(require, "lvim-cmp")
    if ok and type(cmp.capabilities) == "function" then
        return cmp.capabilities()
    end
    return vim.lsp.protocol.make_client_capabilities()
end

return {
    -- earlybird adapter + base OCaml debug configuration (auto-registered with lvim-dap on attach).
    dap = ocaml_dap.spec(),
    -- Per-filetype formatter/linter routing (chosen tools only; empty when none selected — ocaml-lsp
    -- formats via ocamlformat natively by default).
    efm = catalog.efm_groups("ocaml"),
    lsp = {
        root_patterns = { "dune-project", ".git" },
        --- Built fresh per root so the `ocamllsp` binary tracks the project's opam switch.
        ---@return table
        config = function()
            local so = server_opts()
            local ocamllsp = toolchain.resolve("ocaml", "ocaml-lsp", current_root()) or "ocamllsp"
            local cfg = {
                cmd = { ocamllsp },
                filetypes = { "ocaml", "ocaml.interface", "ocamllex", "menhir", "dune" },
                capabilities = capabilities(),
                -- Hand formatting to efm when a formatter is active for the buffer's ft (else ocaml-lsp
                -- formats — ocamlformat natively). Composes any user server on_attach.
                on_attach = catalog.lsp_on_attach("ocaml", "ocaml-lsp"),
            }
            -- Only send non-empty tables: an empty Lua table encodes as a JSON ARRAY ([]), which
            -- servers reject.
            if so.init_options and next(so.init_options) then
                cfg.init_options = so.init_options
            end
            if so.settings and next(so.settings) then
                cfg.settings = so.settings
            end
            return cfg
        end,
    },
}
