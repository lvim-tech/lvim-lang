-- When a server's `settings` / `init_options` are read.
--
-- The declarative providers are loaded by setup(), at startup. astro and vue looked up the
-- TypeScript SDK bundled in their package right there, at module load, and kept the answer. Open
-- an .astro file on a machine without the server: the install prompt installs it, lvim-ls starts
-- it a second later — with the nil that was true at startup. Volar-based servers refuse to start
-- without `typescript.tsdk`, so the first start after an install always failed with "The
-- `typescript.tsdk` init option is required".
--
-- The fix is not local to the two providers: every server entry may now give `settings` and
-- `init_options` as functions, called each time the server is started. The specs below hold the
-- three ways a server config is built (the declarative factory, a hand-written servers/<key>.lua,
-- a companion) to that, and astro / vue to the exact sequence that failed.

describe("lvim-lang: server options are read when the server starts")

local config = require("lvim-lang.config")
local catalog = require("lvim-lang.core.catalog")
local declarative = require("lvim-lang.core.declarative")
local registry_data = require("lvim-lang.providers.registry")

local PKGS = vim.fn.tempname() .. "/packages"

--- Run `fn` with lvim-pkg replaced by a stub whose packages live under PKGS.
---@param fn fun()
local function with_pkg(fn)
    local real = package.loaded["lvim-pkg"]
    package.loaded["lvim-pkg"] = {
        package_path = function(name)
            return PKGS .. "/" .. name
        end,
    }
    local ok, err = pcall(fn)
    package.loaded["lvim-pkg"] = real
    if not ok then
        error(err, 0)
    end
end

--- The config lvim-ls would start `key` with, built the way lvim-ls builds it: a fresh call.
---@param module table  a server-config module (lsp.config)
---@return table
local function start_config(module)
    local cfg = module.lsp.config()
    truthy(type(cfg) == "table", "config() must return a table")
    return cfg
end

for _, case in ipairs({
    { provider = "astro", server = "astro-language-server" },
    { provider = "vue", server = "vue-language-server" },
}) do
    it(case.provider .. ": a server installed after startup still gets its tsdk", function()
        with_pkg(function()
            -- Startup: the provider loads while the package is not installed.
            registry_data.load(require("lvim-lang.providers.registry." .. case.provider))
            local module = declarative.server_module(case.server)
            eq(nil, start_config(module).init_options, "no package, no options (and no bogus path)")

            -- The install prompt installs the server; lvim-ls then starts it.
            local tsdk = PKGS .. "/" .. case.server .. "/node_modules/typescript/lib"
            vim.fn.mkdir(tsdk, "p")
            local cfg = start_config(module)
            eq(tsdk, vim.tbl_get(cfg, "init_options", "typescript", "tsdk"), "the SDK is looked up at start")
        end)
    end)
end

it("a user's own init_options table replaces the default function", function()
    with_pkg(function()
        registry_data.load(require("lvim-lang.providers.registry.astro"))
        config.providers.astro.lsp.servers["astro-language-server"].init_options =
            { typescript = { tsdk = "/my/tsdk" } }
        local cfg = start_config(declarative.server_module("astro-language-server"))
        eq("/my/tsdk", vim.tbl_get(cfg, "init_options", "typescript", "tsdk"))
    end)
end)

it("a hand-written server module calls the function on every start", function()
    local servers = vim.tbl_get(config.providers, "go", "lsp", "servers") or {}
    config.providers.go = config.providers.go or {}
    config.providers.go.lsp = config.providers.go.lsp or {}
    config.providers.go.lsp.servers = servers
    local saved = servers.gopls
    local n = 0
    servers.gopls = vim.tbl_extend("force", saved or {}, {
        settings = function()
            n = n + 1
            return { gopls = { call = n } }
        end,
    })
    local ok, err = pcall(function()
        local module = require("lvim-lang.servers.gopls")
        eq(1, vim.tbl_get(start_config(module), "settings", "gopls", "call"))
        eq(2, vim.tbl_get(start_config(module), "settings", "gopls", "call"), "not frozen after the first start")
    end)
    servers.gopls = saved
    if not ok then
        error(err, 0)
    end
end)

it("a companion resolves its init_options per start too", function()
    config.companions = config.companions or {}
    local value = { a = 1 }
    config.companions["test-companion"] = {
        cmd = { "true" },
        filetypes = { "text" },
        init_options = function()
            return value
        end,
    }
    local ok, err = pcall(function()
        local module = require("lvim-lang.core.companions").server_module("test-companion")
        eq(1, vim.tbl_get(start_config(module), "init_options", "a"))
        value = { a = 2 }
        eq(2, vim.tbl_get(start_config(module), "init_options", "a"), "the companion entry is not replaced")
    end)
    config.companions["test-companion"] = nil
    if not ok then
        error(err, 0)
    end
end)

it("resolve_entry leaves the entry alone and drops a non-table result", function()
    local fn = function()
        return "not a table"
    end
    local entry = { mason = "x", settings = { k = 1 }, init_options = fn }
    local out = catalog.resolve_entry(entry)
    eq(nil, out.init_options, "a non-table result is no options")
    eq(1, out.settings.k)
    eq(fn, entry.init_options, "the catalog entry still holds the function")
    truthy(catalog.resolve_entry(nil) ~= nil, "no entry is an empty table, not nil")
end)
