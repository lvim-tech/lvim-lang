-- lvim-lang.providers.erlang.test: Erlang test running — the EUnit test under the cursor, the whole
-- current module, and the current Common Test suite. EUnit test functions are conventionally named
-- `*_test` (a simple test) or `*_test_` (a test GENERATOR); the enclosing function is found with
-- treesitter (the nearest `fun_decl` / `function_clause` name atom) and run with
-- `rebar3 eunit --test=<module>:<function>` when it is a test function, else the whole module is run
-- (`--module=<module>`). Common Test suites (`*_SUITE.erl`) run through `rebar3 ct --suite=<module>`.
-- All through core.runner → lvim-tasks (Test group, `generic` matcher).
--
---@module "lvim-lang.providers.erlang.test"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The Erlang project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "rebar.config", "erlang.mk", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The module name for a buffer: the source file's basename without the `.erl` extension (Erlang
--- modules are named after their file), or nil when the buffer is not a file.
---@param bufnr integer
---@return string|nil
local function module_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == "" then
        return nil
    end
    return (vim.fs.basename(name):gsub("%.erl$", ""))
end

--- Run `rebar3 <argv…>` for a root through lvim-tasks (Test group, `generic` matcher).
---@param root string
---@param argv string[]
---@param name string
---@return nil
local function run_rebar3(root, argv, name)
    local rebar3 = toolchain.resolve("erlang", "rebar3", root) or "rebar3"
    local cmd = { rebar3 }
    vim.list_extend(cmd, argv)
    runner.run("erlang", { name = name, cmd = cmd, cwd = root, group = "Test", matcher = "generic" })
end

--- The name of the `fun_decl` / `function_clause` enclosing the cursor (treesitter), or nil. The
--- function name is the first `atom` under the clause (tree-sitter-erlang: `function_clause` carries a
--- `name:` field that is an `atom`).
---@param bufnr integer
---@return string|nil
local function enclosing_fn(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil
    end
    while node do
        local t = node:type()
        if t == "function_clause" or t == "fun_decl" then
            local clause = t == "function_clause" and node or nil
            if not clause then
                for child in node:iter_children() do
                    if child:type() == "function_clause" then
                        clause = child
                        break
                    end
                end
            end
            if clause then
                local name = clause:field("name")[1]
                if name then
                    return vim.treesitter.get_node_text(name, bufnr)
                end
            end
        end
        node = node:parent()
    end
    return nil
end

--- `:LvimLang test-func` — run the EUnit test function under the cursor. `*_test` / `*_test_`
--- functions run as `rebar3 eunit --test=<module>:<function>`; the cursor elsewhere falls back to the
--- whole module (`--module=<module>`).
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local module = module_of(ctx.bufnr)
    if not module then
        vim.notify("lvim-lang: no Erlang module for this buffer", vim.log.levels.WARN, TITLE)
        return
    end
    local root = ctx.root or root_of(ctx.bufnr)
    local fn = enclosing_fn(ctx.bufnr)
    if fn and fn:match("_test_?$") then
        run_rebar3(root, { "eunit", "--test=" .. module .. ":" .. fn }, "rebar3 eunit " .. module .. ":" .. fn)
    else
        run_rebar3(root, { "eunit", "--module=" .. module }, "rebar3 eunit " .. module)
    end
end

--- `:LvimLang test-file` — run every EUnit test in the current module (`rebar3 eunit --module=<mod>`).
---@param _args string[]
---@param ctx table
---@return nil
function M.file(_args, ctx)
    local module = module_of(ctx.bufnr)
    if not module then
        vim.notify("lvim-lang: no Erlang module for this buffer", vim.log.levels.WARN, TITLE)
        return
    end
    run_rebar3(ctx.root or root_of(ctx.bufnr), { "eunit", "--module=" .. module }, "rebar3 eunit " .. module)
end

--- `:LvimLang ct-suite` — run the current Common Test suite (`rebar3 ct --suite=<module>`). The
--- buffer must be a `*_SUITE.erl` file.
---@param _args string[]
---@param ctx table
---@return nil
function M.ct_suite(_args, ctx)
    local module = module_of(ctx.bufnr)
    if not module or not module:match("_SUITE$") then
        vim.notify(
            "lvim-lang: not a Common Test suite (open a *_SUITE.erl file) — use :LvimLang ct for the whole project",
            vim.log.levels.WARN,
            TITLE
        )
        return
    end
    run_rebar3(ctx.root or root_of(ctx.bufnr), { "ct", "--suite=" .. module }, "rebar3 ct " .. module)
end

return M
