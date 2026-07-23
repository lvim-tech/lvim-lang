-- lvim-lang.servers.clojure-lsp: the lvim-ls server-config module for clojure-lsp (the Clojure
-- language server). Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the
-- Clojure provider's LSP catalog registers through core.lsp. lvim-lang does NOT own the LSP lifecycle
-- — this module only DESCRIBES the server; the canonical lvim-ls bootstrap starts and manages the
-- client.
--
-- `lsp.config` is a FUNCTION (a seam lvim-ls supports): evaluated fresh per project root, so the
-- `clojure-lsp` binary is resolved per root through core.toolchain (an explicit / mason / PATH one all
-- start correctly). clojure-lsp is a native GraalVM binary launched directly (it needs no JVM to run
-- itself), but it resolves a project's classpath by shelling out to the Clojure CLI / Leiningen — so a
-- `java` must be present; that Java-runtime requirement is surfaced by the provider, not forced here.
-- The `efm` field is PER-FILETYPE (core.catalog.efm_groups): cljfmt (the default formatter) + clj-kondo
-- (the default linter) land on `clojure`, cljfmt on `edn`; formatting is handed to efm on attach so the
-- server does not also format. There is no standard Clojure DAP, so no `dap` field.
--
---@module "lvim-lang.servers.clojure-lsp"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")

--- Clojure's root markers (build-tool project files, then `.git`).
---@type string[]
local ROOT_PATTERNS = {
    "deps.edn",
    "project.clj",
    "build.boot",
    "shadow-cljs.edn",
    ".git",
}

--- The Clojure provider's config block.
---@return table
local function opts()
    return config.providers.clojure or {}
end

--- The clojure-lsp server catalog entry (settings / init_options), from
--- config.providers.clojure.lsp.servers["clojure-lsp"].
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers["clojure-lsp"]) or {}
end

--- Resolve the project root for the current buffer using Clojure's root markers.
---@return string
local function current_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, ROOT_PATTERNS) or vim.fs.dirname(name)
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
    -- Per-filetype formatter/linter routing (chosen efm tools only; empty when none selected).
    efm = catalog.efm_groups("clojure"),
    lsp = {
        root_patterns = ROOT_PATTERNS,
        --- Built fresh per root so the server binary tracks the resolved toolchain (explicit / mason / PATH).
        ---@return table
        config = function()
            local so = server_opts()
            local bin = toolchain.resolve("clojure", "clojure-lsp", current_root()) or "clojure-lsp"
            local cfg = {
                cmd = { bin },
                filetypes = { "clojure", "edn" },
                capabilities = capabilities(),
                -- Hand formatting to efm when a formatter is active for the buffer (cljfmt by default),
                -- else clojure-lsp formats. Composes any user server on_attach.
                on_attach = catalog.lsp_on_attach("clojure", "clojure-lsp"),
            }
            -- Only send settings / init_options when non-empty (an empty Lua table encodes as a JSON
            -- array [], which some servers reject).
            if so.settings and next(so.settings) then
                cfg.settings = so.settings
            end
            if so.init_options and next(so.init_options) then
                cfg.init_options = so.init_options
            end
            return cfg
        end,
    },
}
