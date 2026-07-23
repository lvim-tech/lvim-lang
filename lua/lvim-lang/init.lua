-- lvim-lang: a unified per-language dev-tooling base for the lvim-tech ecosystem.
-- One THIN core (provider registry, toolchain resolution, structured daemon sessions,
-- notification-driven decorations) plus per-language PROVIDERS that plug into it. The core
-- owns none of the heavy machinery — LSP goes through lvim-lsp/lvim-ls, process running
-- through lvim-tasks, debugging through lvim-dap, installation through lvim-pkg, windows
-- through lvim-ui — so a provider is (almost) pure language semantics. Adding a language is a
-- new providers/<lang> module that self-registers; the core is never touched.
--
-- setup() merges user options into lvim-lang.config in place, themes the highlight groups
-- from the live palette, loads the built-in providers (each self-registers via the registry),
-- and installs the :LvimLang command. Everything a provider needs is lazy — nothing is wired
-- for a language until the first buffer of its filetype is opened.
--
---@module "lvim-lang"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local highlights = require("lvim-lang.highlights")
local commands = require("lvim-lang.commands")

local utils = require("lvim-utils.utils")

local M = {}

-- Built-in providers loaded by setup(); each module self-registers on require. Growing this
-- list is how a new first-party language provider ships.
---@type string[]
local BUILTIN_PROVIDERS = {
    "dart",
    "go",
    "rust",
    "python",
    "typescript",
    "cpp",
    "java",
    "csharp",
    "fsharp",
    "ruby",
    "swift",
    "php",
    "kotlin",
    "scala",
    "zig",
    "unison",
    "ocaml",
    "erlang",
    "clojure",
    "elixir",
    "haskell",
}

---@type boolean
local registered = false

--- Configure and start lvim-lang. Idempotent — re-merges config and re-themes; the command
--- and built-in providers are set up once.
---@param opts? LvimLangConfig
---@return nil
function M.setup(opts)
    utils.merge(config, opts or {})
    highlights.setup()

    if registered then
        return
    end
    registered = true

    -- Load every built-in provider EXCEPT those the user disabled — a disabled name is left free for
    -- an external provider to claim it (a clean replace: the built-in never registers, so nothing of it
    -- lingers). See config.disable.
    local disabled = {}
    for _, name in ipairs(config.disable or {}) do
        disabled[name] = true
    end
    for _, name in ipairs(BUILTIN_PROVIDERS) do
        if not disabled[name] then
            require("lvim-lang.providers." .. name)
        end
    end
    commands.setup()
end

-- ── public re-exports (stable seams for other plugins / user config) ──────────

--- Register a language provider (self-registration seam for external providers).
---@param spec LvimLangProvider
---@param defaults? table
---@return nil
function M.register(spec, defaults)
    registry.register(spec, defaults)
end

--- The active provider for a buffer and its resolved root.
---@param bufnr? integer
---@return LvimLangProvider|nil, string|nil
function M.for_buffer(bufnr)
    return registry.for_buffer(bufnr)
end

--- Registered provider names.
---@return string[]
function M.providers()
    return registry.names()
end

--- The statusline segment for a buffer (the active provider's), for a user's statusline.
---   require("lvim-lang").status()
---@param bufnr? integer
---@return string
function M.status(bufnr)
    return require("lvim-lang.core.ui").statusline(bufnr)
end

return M
