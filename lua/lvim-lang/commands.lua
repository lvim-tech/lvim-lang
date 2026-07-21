-- lvim-lang.commands: the single :LvimLang user command.
-- A small tree: a few CORE subcommands (status, providers) plus PROVIDER subcommands resolved
-- against the active buffer's provider — so :LvimLang run in a Dart buffer dispatches to the
-- Dart provider's `run`, while the same command in a Rust buffer would reach Rust's. Completion
-- offers the core subs merged with whatever the current buffer's provider exposes.
--
---@module "lvim-lang.commands"

local registry = require("lvim-lang.registry")

local M = {}

-- Core subcommands, always available regardless of the active buffer.
---@type table<string, fun(args?: string[])>
local core_subs = {}

--- Report plugin status: enabled state and the registered providers.
---@return nil
function core_subs.status()
    local config = require("lvim-lang.config")
    local names = registry.names()
    table.sort(names)
    vim.notify(
        ("lvim-lang: enabled=%s  providers=%s"):format(
            tostring(config.enabled),
            #names > 0 and table.concat(names, ", ") or "(none)"
        ),
        vim.log.levels.INFO,
        { title = "lvim-lang" }
    )
end

--- Resolve and report the active buffer's provider toolchain (each declared tool → path).
---@return nil
function core_subs.toolchain()
    local provider, root = registry.for_buffer()
    if not provider or not root then
        vim.notify("lvim-lang: no language provider for this buffer", vim.log.levels.WARN, { title = "lvim-lang" })
        return
    end
    if not provider.toolchain then
        vim.notify(
            "lvim-lang: " .. provider.name .. " declares no toolchain",
            vim.log.levels.INFO,
            { title = "lvim-lang" }
        )
        return
    end
    local tc = require("lvim-lang.core.toolchain")
    local tools = vim.tbl_keys(provider.toolchain.tools)
    table.sort(tools)
    local lines = {}
    for _, tool in ipairs(tools) do
        local path, reason = tc.resolve(provider.name, tool, root)
        lines[#lines + 1] = ("%s: %s"):format(tool, path or ("not found — " .. (reason or "?")))
    end
    vim.notify(
        provider.name .. " toolchain (" .. root .. ")\n  " .. table.concat(lines, "\n  "),
        vim.log.levels.INFO,
        { title = "lvim-lang" }
    )
end

--- List registered providers, one per line.
---@return nil
function core_subs.providers()
    local names = registry.names()
    table.sort(names)
    vim.notify(
        #names > 0 and ("Providers:\n  " .. table.concat(names, "\n  ")) or "No providers registered.",
        vim.log.levels.INFO,
        { title = "lvim-lang" }
    )
end

--- Dispatch a :LvimLang invocation. Core subs win; otherwise the active provider's command
--- of that name runs, with the remaining args and a context table.
---@param fargs string[]
---@return nil
local function dispatch(fargs)
    local sub = fargs[1]
    if not sub or sub == "" then
        return core_subs.status()
    end
    local rest = { unpack(fargs, 2) }
    if core_subs[sub] then
        return core_subs[sub](rest)
    end
    local provider, root = registry.for_buffer()
    if not provider then
        vim.notify("lvim-lang: no language provider for this buffer", vim.log.levels.WARN, { title = "lvim-lang" })
        return
    end
    local cmd = provider.commands and provider.commands[sub]
    if not cmd then
        vim.notify(
            ("lvim-lang: unknown command '%s' for %s"):format(sub, provider.name),
            vim.log.levels.WARN,
            { title = "lvim-lang" }
        )
        return
    end
    cmd.impl(rest, { provider = provider, root = root, bufnr = vim.api.nvim_get_current_buf() })
end

--- Completion. First token: core subs + the active provider's command names. Beyond that,
--- delegate to the chosen provider command's own `complete` (e.g. `pub get|upgrade`).
---@param arg string
---@param line string
---@return string[]
local function complete(arg, line)
    local words = vim.split(vim.trim(line), "%s+")
    -- Completing an ARGUMENT to a subcommand (a 3rd+ token, or a trailing space after the sub).
    if #words > 2 or (#words == 2 and arg == "") then
        local provider = registry.for_buffer()
        local cmd = provider and provider.commands and provider.commands[words[2]]
        if cmd and cmd.complete then
            return cmd.complete(arg, line)
        end
        return {}
    end
    -- First token: core subs + provider command names.
    local items = vim.tbl_keys(core_subs)
    local provider = registry.for_buffer()
    if provider and provider.commands then
        for name in pairs(provider.commands) do
            items[#items + 1] = name
        end
    end
    table.sort(items)
    return vim.tbl_filter(function(c)
        return arg == "" or c:find(arg, 1, true) == 1
    end, items)
end

--- Install the :LvimLang command (once).
---@return nil
function M.setup()
    vim.api.nvim_create_user_command("LvimLang", function(cmd)
        dispatch(cmd.fargs)
    end, {
        nargs = "*",
        complete = complete,
        desc = "lvim-lang: status / providers / <provider command>",
    })
end

return M
