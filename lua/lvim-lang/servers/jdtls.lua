-- lvim-lang.servers.jdtls: the lvim-ls server-config module for jdtls (the Eclipse JDT language
-- server). Loaded by the lvim-ls manager via the "lvim-lang.servers" dir prefix that the Java
-- provider's LSP catalog registers through core.lsp. lvim-lang does NOT own the LSP lifecycle — this
-- module only DESCRIBES the server; the canonical lvim-ls bootstrap starts and manages the client.
--
-- jdtls is unlike the other servers in two ways, both handled by the per-root `lsp.config` FUNCTION:
--   * it is launched through the mason `jdtls` WRAPPER (a Python launcher that locates the Equinox
--     jar + platform config itself) and REQUIRES a per-project `-data <workspace>` directory — a
--     persistent scratch area jdtls writes its index into. The workspace is resolved under a stable
--     cache location keyed by the project root, so each project gets its own (never shared, never
--     recreated per session).
--   * debugging lives IN the server: the java-debug / java-test bundle jars are handed to jdtls via
--     `init_options.bundles`, after which it exposes `vscode.java.startDebugSession` (see the dap
--     module's adapter). The `dap` field below carries that adapter + the base configurations.
--
---@module "lvim-lang.servers.jdtls"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local catalog = require("lvim-lang.core.catalog")
local java_dap = require("lvim-lang.providers.java.dap")

--- Java's root markers (Gradle / Maven project files, then `.git`).
---@type string[]
local ROOT_PATTERNS = {
    "settings.gradle",
    "settings.gradle.kts",
    "build.gradle",
    "build.gradle.kts",
    "pom.xml",
    ".git",
}

--- The Java provider's config block.
---@return table
local function opts()
    return config.providers.java or {}
end

--- The jdtls server catalog entry (settings / init_options).
---@return table
local function server_opts()
    local lsp = opts().lsp or {}
    return (lsp.servers and lsp.servers.jdtls) or {}
end

--- Resolve the project root for the current buffer using Java's root markers.
---@return string
local function current_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, ROOT_PATTERNS) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The per-project jdtls DATA workspace directory for a root: `<workspace_root>/<sanitized-root>`,
--- with `workspace_root` defaulting to `stdpath("cache")/jdtls`. The sanitized key (path separators
--- and other non-word characters folded to `_`) makes each project's workspace stable and unique.
---@param root string
---@return string
local function workspace_dir(root)
    local base = opts().workspace_root or vim.fs.joinpath(vim.fn.stdpath("cache"), "jdtls")
    local key = root:gsub("[^%w%-]", "_")
    return vim.fs.joinpath(base, key)
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
    -- java-debug adapter + base java debug configurations (auto-registered with lvim-dap on attach).
    dap = java_dap.spec(),
    -- Per-filetype formatter/linter routing (chosen efm tools only; empty when none selected).
    efm = catalog.efm_groups("java"),
    lsp = {
        root_patterns = ROOT_PATTERNS,
        --- Built fresh per root so the jdtls launcher, the `-data` workspace and the loaded debug
        --- bundles all track the project being opened.
        ---@return table
        config = function()
            local root = current_root()
            local so = server_opts()
            local jdtls = toolchain.resolve("java", "jdtls", root) or "jdtls"
            local workspace = workspace_dir(root)
            vim.fn.mkdir(workspace, "p")
            local cfg = {
                -- The mason `jdtls` launcher finds the Equinox launcher + platform config itself; it
                -- only needs the per-project data directory.
                cmd = { jdtls, "-data", workspace },
                filetypes = { "java" },
                capabilities = capabilities(),
                -- Hand formatting to efm when a formatter is active for the buffer (else jdtls
                -- formats). Composes any user server on_attach.
                on_attach = catalog.lsp_on_attach("java", "jdtls"),
            }
            -- Only send settings when non-empty (an empty Lua table encodes as a JSON array []).
            if so.settings and next(so.settings) then
                cfg.settings = so.settings
            end
            -- init_options: the user's, plus the java-debug / java-test bundle jars so jdtls exposes
            -- its debug + test-launch commands. Merge without mutating the shared config table.
            local init = vim.deepcopy(so.init_options or {})
            local bundles = java_dap.bundles()
            if #bundles > 0 then
                init.bundles = vim.list_extend(init.bundles or {}, bundles)
            end
            if next(init) then
                cfg.init_options = init
            end
            return cfg
        end,
    },
}
