-- lvim-lang.core.daemon: a generic client for long-lived, line-framed structured sessions.
-- This is the ONE piece of process handling lvim-lang owns itself, because lvim-tasks models
-- fire-and-collect jobs, not a persistent request/response + event stream like
-- `flutter run --machine`. The core provides jobstart (headless, no terminal), newline framing,
-- id-correlated requests and event dispatch; the MESSAGE SEMANTICS (which methods, which events,
-- how a line decodes) live entirely in the provider's codec + on_event.
--
---@module "lvim-lang.core.daemon"

---@class LvimLangDaemonCodec
---@field decode fun(line: string): table|nil   Parse a protocol line (nil = not a protocol message)
---@field encode fun(msg: table): string        Serialize an outgoing message

---@class LvimLangDaemonOpts
---@field cmd      string[]                                Argv (toolchain-resolved binary + args)
---@field cwd      string                                  Working directory (project root)
---@field codec    LvimLangDaemonCodec                     Line codec (protocol-specific)
---@field on_event fun(event: string, params: table)       Protocol event arrived
---@field on_line? fun(line: string)                        Non-protocol stdout/stderr line (for the dev log)
---@field on_exit? fun(code: integer)                       Process exited

---@class LvimLangDaemonSession
---@field request fun(self, method: string, params?: table, cb?: fun(err: any, result: any))
---@field notify  fun(self, method: string, params?: table)
---@field stop    fun(self)
---@field alive   fun(self): boolean
---@field job_id  integer

local M = {}

--- Start a structured daemon session. Returns nil when the job fails to start.
---@param opts LvimLangDaemonOpts
---@return LvimLangDaemonSession|nil
function M.start(opts)
    ---@type LvimLangDaemonSession
    local session = setmetatable({ job_id = -1 }, { __index = {} })
    local next_id = 1
    local pending = {} ---@type table<integer, fun(err: any, result: any)>

    --- Route one decoded protocol message: a response (id + result/error) resolves a pending
    --- request; an event goes to on_event. Non-protocol lines are handled by the caller.
    ---@param line string
    local function handle_line(line)
        if line == "" then
            return
        end
        local msg = opts.codec.decode(line)
        if not msg then
            if opts.on_line then
                opts.on_line(line)
            end
            return
        end
        if msg.id ~= nil and msg.method == nil then
            local cb = pending[msg.id]
            pending[msg.id] = nil
            if cb then
                cb(msg.error, msg.result)
            end
        elseif msg.event then
            opts.on_event(msg.event, msg.params or {})
        end
    end

    -- Newline reassembly across chunks: data[1] continues the previous chunk's trailing partial;
    -- each further element was preceded by a "\n" and so completes a line.
    local partial = ""
    ---@param data string[]
    local function on_stream(_, data)
        if not data then
            return
        end
        partial = partial .. data[1]
        for i = 2, #data do
            handle_line(partial)
            partial = data[i]
        end
    end

    local job = vim.fn.jobstart(opts.cmd, {
        cwd = opts.cwd,
        stdout_buffered = false,
        stderr_buffered = false,
        on_stdout = on_stream,
        on_stderr = function(_, data)
            if not data or not opts.on_line then
                return
            end
            for _, line in ipairs(data) do
                if line ~= "" then
                    opts.on_line(line)
                end
            end
        end,
        on_exit = function(_, code)
            if opts.on_exit then
                opts.on_exit(code)
            end
        end,
    })
    if job <= 0 then
        return nil
    end
    session.job_id = job

    local methods = getmetatable(session).__index

    --- Send an id-correlated request; `cb(err, result)` fires on the matching response.
    ---@param method string
    ---@param params? table
    ---@param cb? fun(err: any, result: any)
    function methods:request(method, params, cb)
        local id = next_id
        next_id = next_id + 1
        if cb then
            pending[id] = cb
        end
        vim.fn.chansend(self.job_id, opts.codec.encode({ id = id, method = method, params = params }) .. "\n")
    end

    --- Send a fire-and-forget notification (no id).
    ---@param method string
    ---@param params? table
    function methods:notify(method, params)
        vim.fn.chansend(self.job_id, opts.codec.encode({ method = method, params = params }) .. "\n")
    end

    --- Stop the session's process.
    function methods:stop()
        pcall(vim.fn.jobstop, self.job_id)
    end

    --- Whether the process is still running.
    ---@return boolean
    function methods:alive()
        return vim.fn.jobwait({ self.job_id }, 0)[1] == -1
    end

    return session
end

return M
