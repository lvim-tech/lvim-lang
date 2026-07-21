-- lvim-lang.providers.dart.sdk: install the Flutter SDK through lvim-pkg.
-- When Flutter is not resolvable, `:LvimLang install` clones the SDK (a git repo + channel/tag,
-- both configurable) via lvim-pkg's `sdk` handler, which links the flutter/dart bins into the
-- lvim-pkg bin dir. On success the toolchain cache is invalidated so the new SDK resolves.
--
---@module "lvim-lang.providers.dart.sdk"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")

local TITLE = { title = "lvim-lang" }

local M = {}

--- `:LvimLang install` — clone/install the configured Flutter SDK through lvim-pkg.
---@param _args string[]
---@param ctx table  { provider, root, bufnr }
---@return nil
function M.install(_args, ctx)
    local ok, pkg = pcall(require, "lvim-pkg")
    if not ok or type(pkg.install_sdk) ~= "function" then
        vim.notify("lvim-lang: lvim-pkg with SDK support is not available", vim.log.levels.WARN, TITLE)
        return
    end
    local sdk = (config.providers.dart and config.providers.dart.sdk) or {}
    vim.notify("lvim-lang: installing the Flutter SDK (this can take a while)…", vim.log.levels.INFO, TITLE)
    pkg.install_sdk({
        name = "flutter",
        repo = sdk.repo or "https://github.com/flutter/flutter.git",
        ref = sdk.ref or "stable",
        bins = { "flutter", "dart" },
        version = sdk.ref or "stable",
    }, function(err)
        if err then
            vim.notify("lvim-lang: Flutter SDK install failed — " .. err, vim.log.levels.ERROR, TITLE)
            return
        end
        toolchain.invalidate("dart", ctx.root)
        vim.notify("lvim-lang: Flutter SDK installed", vim.log.levels.INFO, TITLE)
    end, {
        on_progress = function(_, _, action)
            vim.notify("lvim-lang: flutter SDK — " .. action, vim.log.levels.INFO, TITLE)
        end,
    })
end

return M
