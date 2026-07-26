-- lvim-lang.providers.scala.devlog: metals' session messages → the shared dev-log panel.
--
-- The SECOND consumer of `lvim-lang.core.log` (the first is Flutter), and the reason the panel is
-- shared infrastructure rather than a Flutter feature: a Scala session has exactly the same shape —
-- a long-lived server that narrates work the editor cannot otherwise show. Metals imports the build,
-- starts Bloop, compiles and indexes for minutes at a time, and says so only through its own LSP
-- notifications. Without somewhere to put them, "why is nothing working yet" has no answer.
--
-- Why LSP handlers and not `core.daemon`: metals OWNS its build server (Bloop over BSP) and speaks to
-- us as a language server, so there is no separate process to frame — the "session stream" IS the
-- server's notification traffic. Three messages carry it:
--
--   metals/status      the short status line the editor would put in a status bar ("Importing build",
--                      "Compiling …", "Indexing"). Deduplicated: metals repeats the same text often.
--   window/logMessage  the server's own log — build import output, Bloop diagnostics, stack traces.
--   metals/slowTask    a REQUEST announcing a long operation. It expects a reply, so the handler must
--                      answer `{ cancel = false }`; not answering leaves metals waiting.
--
-- `$/progress` is deliberately NOT hooked: Neovim already routes it to the progress UI, and mirroring
-- it here would duplicate that in two places.
--
---@module "lvim-lang.providers.scala.devlog"

local config = require("lvim-lang.config")
local log = require("lvim-lang.core.log")

local M = {}

-- LSP MessageType → the dev log's line kind. The panel has three kinds, LSP has four levels, so a
-- warning reads as `info` (coloured, but not alarming) — only a real error gets the red row.
---@type table<integer, string>
local KIND = { [1] = "error", [2] = "info", [3] = "info", [4] = "normal" }

-- The last status text per root, so metals' repeated status pings do not fill the ring.
---@type table<string, string>
local last_status = {}

--- The Scala provider's dev-log options.
---@return table
local function opts()
    return (config.providers.scala or {}).dev_log or {}
end

--- The project root of the client that sent a message.
---@param ctx table  the LSP handler context
---@return string?
local function root_of(ctx)
    local client = ctx and ctx.client_id and vim.lsp.get_client_by_id(ctx.client_id) or nil
    return client and client.root_dir or nil
end

--- Append `line` to `root`'s dev log, naming the panel on first use.
---@param root string?
---@param line string?
---@param kind string
---@return nil
local function append(root, line, kind)
    if not root or not line or line == "" then
        return
    end
    -- The panel is shared, so it wears the name of whoever is streaming into it.
    log.set_title(root, opts().title or "Metals Dev Log", opts().icon or "󰘧")
    for _, part in ipairs(vim.split(line, "\n", { plain = true, trimempty = true })) do
        log.append(root, part, kind)
    end
end

--- The LSP handlers metals' client config installs. Returns an empty table when routing is disabled,
--- so the server config can merge it unconditionally.
---@return table<string, fun(err: any, result: any, ctx: table): any>
function M.handlers()
    local o = opts()
    if o.enabled == false then
        return {}
    end
    local handlers = {}

    if o.status ~= false then
        handlers["metals/status"] = function(_, result, ctx)
            local root = root_of(ctx)
            local text = result and result.text or nil
            if not root or not text or text == "" then
                return
            end
            -- metals re-sends the same status on a timer; only transitions are worth a row.
            if last_status[root] == text then
                return
            end
            last_status[root] = text
            append(root, text, result.level == "error" and "error" or "info")
        end
    end

    if o.messages ~= false then
        handlers["window/logMessage"] = function(_, result, ctx)
            local level = tonumber(result and result.type) or 4
            -- `min_level` follows the LSP numbering (1 error … 4 log): a HIGHER number is chattier, so
            -- a message is kept while its level is at or above the configured verbosity.
            if level > (tonumber(o.min_level) or 3) then
                return
            end
            append(root_of(ctx), result and result.message, KIND[level] or "normal")
        end
    end

    if o.slow_task ~= false then
        handlers["metals/slowTask"] = function(_, result, ctx)
            append(root_of(ctx), result and result.text, "info")
            -- metals BLOCKS on this reply — it is asking whether the user wants to cancel the task.
            return { cancel = false }
        end
    end

    return handlers
end

--- Drop a root's remembered status (used when the client detaches, so a restarted session logs its
--- first status again instead of silently skipping it as a repeat).
---@param root string?
---@return nil
function M.forget(root)
    if root then
        last_status[root] = nil
    end
end

return M
