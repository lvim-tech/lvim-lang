-- lvim-lang.providers.ruby.dap: Ruby debugging through lvim-dap, backed by rdbg.
-- rdbg is the remote debugger shipped by the `debug` gem (`bundle add debug`) — NOT a mason package,
-- so it is resolved through the toolchain (a project binstub / the selected ruby's bin / PATH), never
-- installed here. The adapter is a `server` adapter that LAUNCHES rdbg opening a DAP server on a free
-- port (`rdbg --open --port <p> -c -- <command> <script>`) and connects to it; lvim-dap resolves the
-- `${port}`. Base configurations cover debugging the current ruby file. `:LvimLang debug` continues /
-- starts a session; `:LvimLang debug-test` debugs exactly the RSpec example under the cursor
-- (`bundle exec rspec <file>:<line>` under rdbg).
--
---@module "lvim-lang.providers.ruby.dap"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The Ruby provider's config block.
---@return table
local function opts()
    return config.providers.ruby or {}
end

--- The Ruby project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "Gemfile", "Rakefile", ".ruby-version", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Resolve the rdbg binary for `root`: the toolchain resolution (config → binstub → ruby bin → PATH),
--- else the bare name (so the error surfaces at launch with a clear "install the debug gem" hint).
---@param root string
---@return string
local function rdbg_bin(root)
    return toolchain.resolve("ruby", "rdbg", root) or "rdbg"
end

--- The rdbg `server` adapter factory. rdbg is launched with `--open --port ${port} -c -- <command>
--- <script>`; `command` (default "ruby") is split on whitespace so a multi-word command like
--- "bundle exec rspec" expands to separate argv entries. lvim-dap fills in the free `${port}`.
---@return fun(callback: fun(adapter: table), config: table)
local function adapter()
    return function(callback, dap_config)
        local root = dap_config.cwd or vim.uv.cwd() or "."
        local command = dap_config.command or "ruby"
        local args = { "--open", "--port", "${port}", "-c", "--" }
        vim.list_extend(args, vim.split(command, "%s+", { trimempty = true }))
        args[#args + 1] = dap_config.script or "${file}"
        callback({
            type = "server",
            host = "127.0.0.1",
            port = "${port}",
            executable = { command = rdbg_bin(root), args = args },
        })
    end
end

--- The static `dap` field for the ruby-lsp server config (adapter + base configurations). rdbg opens
--- its own server, so the configurations `attach` to it (lvim-dap launches rdbg via the adapter's
--- `executable`, then attaches).
---@return table
function M.spec()
    return {
        adapters = { ruby = adapter() },
        configurations = {
            ruby = {
                {
                    type = "ruby",
                    request = "attach",
                    name = "Debug current file (ruby)",
                    command = "ruby",
                    script = "${file}",
                    cwd = "${workspaceFolder}",
                },
                {
                    type = "ruby",
                    request = "attach",
                    name = "Debug current file (bundle exec ruby)",
                    command = "bundle exec ruby",
                    script = "${file}",
                    cwd = "${workspaceFolder}",
                },
            },
        },
    }
end

--- `:LvimLang debug` — continue / start a debug session (lvim-dap picks a configuration).
---@param _args string[]
---@param _ctx table
---@return nil
function M.debug(_args, _ctx)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok then
        vim.notify("lvim-lang: lvim-dap not available", vim.log.levels.WARN, TITLE)
        return
    end
    dap.continue()
end

--- `:LvimLang debug-test` — debug exactly the RSpec example under the cursor. Runs
--- `bundle exec rspec <file>:<line>` under rdbg (the example addressed by its line) and attaches.
---@param _args string[]
---@param ctx table
---@return nil
function M.debug_test(_args, ctx)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok then
        vim.notify("lvim-lang: lvim-dap not available", vim.log.levels.WARN, TITLE)
        return
    end
    local bufnr = ctx.bufnr
    local file = vim.api.nvim_buf_get_name(bufnr)
    if file == "" then
        vim.notify("lvim-lang: no file for this buffer", vim.log.levels.WARN, TITLE)
        return
    end
    -- The example is addressed by the line RSpec resolves to the enclosing `it`/`example` block.
    local line = require("lvim-lang.providers.ruby.test").example_line(bufnr)
    local root = ctx.root or root_of(bufnr)
    local o = opts()
    -- `bundle exec` when the project has a Gemfile and bundler resolves, else run rspec directly.
    local exec = "rspec"
    if vim.fn.filereadable(vim.fs.joinpath(root, "Gemfile")) == 1 and toolchain.resolve("ruby", "bundle", root) then
        exec = "bundle exec rspec"
    end
    dap.run({
        type = "ruby",
        request = "attach",
        name = "Debug rspec " .. vim.fs.basename(file) .. ":" .. line,
        command = o.debug_rspec_command or exec,
        script = file .. ":" .. line,
        cwd = "${workspaceFolder}",
    })
end

return M
