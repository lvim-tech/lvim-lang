-- lvim-lang.providers.rust.dap: Rust debugging through lvim-dap, backed by CodeLLDB.
-- The static adapter + base launch configurations are handed to lvim-ls via the rust-analyzer server
-- config's `dap` field (auto-registered with lvim-dap on attach). CodeLLDB runs as a `server` adapter
-- (`codelldb --port ${port}`, a free port lvim-dap resolves). `:LvimLang debug` continues/starts a
-- session; `:LvimLang debug-test` builds the test binary (`cargo test --no-run`) and launches it under
-- the debugger with `--exact <name>` for the test under the cursor.
--
---@module "lvim-lang.providers.rust.dap"

local toolchain = require("lvim-lang.core.toolchain")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The Cargo crate root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "Cargo.toml", "Cargo.lock", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Resolve the CodeLLDB binary: an explicit config path → PATH (the mason install).
---@return string
local function codelldb_bin()
    local o = require("lvim-lang.config").providers.rust or {}
    if o.codelldb_path and vim.fn.executable(o.codelldb_path) == 1 then
        return o.codelldb_path
    end
    local p = vim.fn.exepath("codelldb")
    return p ~= "" and p or "codelldb"
end

--- The CodeLLDB server adapter: `codelldb --port ${port}` (lvim-dap resolves a free port).
---@return fun(callback: fun(adapter: table), config: table)
local function adapter()
    return function(callback, _config)
        callback({
            type = "server",
            port = "${port}",
            executable = { command = codelldb_bin(), args = { "--port", "${port}" } },
        })
    end
end

--- The static `dap` field for the rust-analyzer server config (adapter + base configurations).
---@return table
function M.spec()
    return {
        adapters = { codelldb = adapter() },
        configurations = {
            rust = {
                {
                    type = "codelldb",
                    request = "launch",
                    name = "Debug binary",
                    program = function()
                        local root = require("lvim-lang.providers.rust.tasks").root()
                        return vim.fn.input("Path to binary: ", root .. "/target/debug/", "file")
                    end,
                    cwd = "${workspaceFolder}",
                    stopOnEntry = false,
                },
            },
        },
    }
end

--- The name of the function_item enclosing the cursor (treesitter), or nil.
---@param bufnr integer
---@return string|nil
local function enclosing_fn(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil
    end
    while node do
        if node:type() == "function_item" then
            local name_node = node:field("name")[1]
            return name_node and vim.treesitter.get_node_text(name_node, bufnr) or nil
        end
        node = node:parent()
    end
    return nil
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

--- `:LvimLang debug-test` — build the test binary (`cargo test --no-run`, JSON output to locate the
--- executable) and launch it under CodeLLDB filtered to the test under the cursor (`--exact <name>`).
---@param _args string[]
---@param ctx table
---@return nil
function M.debug_test(_args, ctx)
    local ok, dap = pcall(require, "lvim-dap")
    if not ok then
        vim.notify("lvim-lang: lvim-dap not available", vim.log.levels.WARN, TITLE)
        return
    end
    local name = enclosing_fn(ctx.bufnr)
    if not name then
        vim.notify("lvim-lang: cursor is not inside a test function", vim.log.levels.WARN, TITLE)
        return
    end
    local root = ctx.root or root_of(ctx.bufnr)
    local cargo = toolchain.resolve("rust", "cargo", root) or "cargo"
    vim.notify("lvim-lang: building the test binary…", vim.log.levels.INFO, TITLE)
    -- --message-format=json emits one JSON object per artifact; the test executable is the entry with
    -- profile.test == true and a non-null `executable`.
    vim.system({ cargo, "test", "--no-run", "--message-format=json" }, { cwd = root, text = true }, function(res)
        vim.schedule(function()
            if res.code ~= 0 then
                vim.notify("lvim-lang: cargo test --no-run failed: " .. (res.stderr or ""), vim.log.levels.ERROR, TITLE)
                return
            end
            local exe
            for _, line in ipairs(vim.split(res.stdout or "", "\n")) do
                local okj, obj = pcall(vim.json.decode, line)
                if okj and type(obj) == "table" and obj.executable and obj.profile and obj.profile.test then
                    exe = obj.executable
                end
            end
            if not exe then
                vim.notify("lvim-lang: could not locate the test binary", vim.log.levels.ERROR, TITLE)
                return
            end
            dap.run({
                type = "codelldb",
                request = "launch",
                name = "Debug test " .. name,
                program = exe,
                args = { "--exact", name, "--nocapture" },
                cwd = "${workspaceFolder}",
                stopOnEntry = false,
            })
        end)
    end)
end

return M
