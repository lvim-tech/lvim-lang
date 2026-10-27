-- What a DEFERRED debug session may still read.
--
-- `:LvimLang debug-test` on Scala cannot ask metals for a debug adapter immediately: the server
-- starts one asynchronously, so the request waits out `debug_attach_delay_ms`. The question this
-- spec settles is what the deferred call is allowed to touch. A buffer handle is not a value; it
-- is a reference that stops being valid the moment the user closes the file — and half a second
-- is plenty of time to close a file. Read inside the timer, `nvim_buf_get_name` raises "Invalid
-- buffer id" and the session never starts, with no error the user can connect to anything.
--
-- So: everything that comes from the buffer is resolved BEFORE the wait, and the deferred call
-- carries values only. Java and Kotlin already worked this way (their class/method are strings
-- long before the defer); Scala was the one provider reading the buffer late.

describe("lvim-lang: a deferred debug session reads the buffer before it waits")

local config = require("lvim-lang.config")
local scala_dap = require("lvim-lang.providers.scala.dap")

--- Run `debug_test` against a stubbed lvim-dap and return the configuration it was handed.
--- `mutate` runs after the call but BEFORE the timer fires — that window is the whole point.
---@param bufnr integer
---@param mutate? fun()
---@return table|nil config
---@return table[] notifications
local function run_debug_test(bufnr, mutate)
    local captured, notes = nil, {}

    local real_dap = package.loaded["lvim-dap"]
    local real_notify = vim.notify
    package.loaded["lvim-dap"] = {
        run = function(cfg)
            captured = cfg
        end,
        continue = function() end,
    }
    vim.notify = function(msg, level)
        notes[#notes + 1] = { msg = msg, level = level }
    end

    config.providers = config.providers or {}
    config.providers.scala = config.providers.scala or {}
    local real_delay = config.providers.scala.debug_attach_delay_ms
    config.providers.scala.debug_attach_delay_ms = 10

    local ok, err = pcall(scala_dap.debug_test, {}, { bufnr = bufnr })
    if mutate then
        mutate()
    end
    -- Long enough for the 10 ms timer; vim.wait pumps the event loop, so the deferred call runs.
    vim.wait(400, function()
        return captured ~= nil
    end)

    config.providers.scala.debug_attach_delay_ms = real_delay
    package.loaded["lvim-dap"] = real_dap
    vim.notify = real_notify

    truthy(ok, "debug_test itself raised: " .. tostring(err))
    return captured, notes
end

--- A named, listed buffer, as a user's open test file.
---@param name string
---@return integer
local function buffer_named(name)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, name)
    return buf
end

it("hands metals the file's tail name and its URI", function()
    local buf = buffer_named(vim.fn.tempname() .. "/FooSpec.scala")
    local cfg = run_debug_test(buf)
    truthy(cfg, "lvim-dap.run was never called")
    eq("scala", cfg.type)
    eq("launch", cfg.request)
    eq("Debug tests in FooSpec.scala", cfg.name)
    eq("testFile", cfg.metals.runType)
    eq(vim.uri_from_bufnr(buf), cfg.metals.path)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
end)

it("still starts the session when the buffer is closed during the wait", function()
    local path = vim.fn.tempname() .. "/GoneSpec.scala"
    local buf = buffer_named(path)
    local uri = vim.uri_from_bufnr(buf)

    local cfg = run_debug_test(buf, function()
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    -- This is the case that fails against reading the buffer inside the timer: there, the
    -- closure raises on an invalid handle and `run` is never reached at all.
    truthy(cfg, "lvim-dap.run was never called: the deferred closure read a buffer that was gone")
    eq("Debug tests in GoneSpec.scala", cfg.name)
    eq(uri, cfg.metals.path)
    truthy(not vim.api.nvim_buf_is_valid(buf), "the buffer was supposed to be gone")
end)

it("refuses up front when the buffer is already invalid", function()
    local buf = buffer_named(vim.fn.tempname() .. "/DeadSpec.scala")
    vim.api.nvim_buf_delete(buf, { force = true })

    local cfg, notes = run_debug_test(buf)
    eq(nil, cfg, "no session may be started for a buffer that does not exist")
    truthy(#notes > 0, "the refusal has to say something")
    truthy(notes[1].msg:match("no buffer"), "unexpected message: " .. tostring(notes[1].msg))
    eq(vim.log.levels.WARN, notes[1].level)
end)
