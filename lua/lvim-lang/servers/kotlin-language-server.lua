-- lvim-lang.servers.kotlin-language-server: the lvim-ls server-config module for the Kotlin language
-- server (fwcd/kotlin-language-server). Loaded by the lvim-ls manager via the "lvim-lang.servers" dir
-- prefix that the Kotlin provider's LSP catalog registers through core.lsp. lvim-lang does NOT own the
-- LSP lifecycle — this module only DESCRIBES the server; the canonical lvim-ls bootstrap starts and
-- manages the client.
--
-- `lsp.config` is a FUNCTION (a seam lvim-ls supports): evaluated fresh per project root, so the
-- `kotlin-language-server` binary is resolved per root through core.toolchain (a version-managed
-- toolchain in one project and the PATH one in another both start correctly). The server is a JVM
-- program launched through the mason wrapper script (which locates a `java` itself) — the Java-runtime
-- requirement is surfaced by the provider, not forced here. The `efm` field is PER-FILETYPE
-- (core.catalog.efm_groups): ktlint (the default formatter/linter) lands on `kotlin`; formatting is
-- handed to efm on attach so the server does not also format. Debugging is a STANDALONE adapter
-- (providers.kotlin.dap), carried on the `dap` field and auto-registered with lvim-dap on attach.
--
---@module "lvim-lang.servers.kotlin-language-server"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local kotlin_dap = require("lvim-lang.providers.kotlin.dap")

--- Kotlin's root markers (Gradle scripts / wrapper, then `.git`).
---@type string[]
local ROOT_PATTERNS = {
    "build.gradle.kts",
    "build.gradle",
    "settings.gradle.kts",
    "settings.gradle",
    ".git",
}

--- The Kotlin provider's config block.
---@return table
local function opts()
    return config.providers.kotlin or {}
end

--- The kotlin-language-server catalog entry (settings / init_options), from
--- config.providers.kotlin.lsp.servers["kotlin-language-server"].
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers["kotlin-language-server"]) or {}
end

--- Resolve the project root for the current buffer using Kotlin's root markers.
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
    -- kotlin-debug-adapter + base kotlin debug configurations (auto-registered with lvim-dap on attach).
    dap = kotlin_dap.spec(),
    -- Per-filetype formatter/linter routing (chosen efm tools only; empty when none selected).
    efm = catalog.efm_groups("kotlin"),
    lsp = {
        root_patterns = ROOT_PATTERNS,
        --- Built fresh per root so the server binary tracks the project's toolchain (version manager / PATH).
        ---@return table
        config = function()
            local so = server_opts()
            local kls = toolchain.resolve("kotlin", "kotlin-language-server", current_root())
                or "kotlin-language-server"
            local cfg = {
                cmd = { kls },
                filetypes = { "kotlin" },
                capabilities = capabilities(),
                -- Hand formatting to efm when a formatter is active for the buffer (ktlint by
                -- default), else the server formats. Composes any user server on_attach.
                on_attach = catalog.lsp_on_attach("kotlin", "kotlin-language-server"),
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
