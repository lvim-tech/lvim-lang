-- lvim-lang.providers.ocaml.test: OCaml test running through dune.
-- OCaml has no single test protocol — alcotest / ounit / the inline expect-tests each register with
-- dune's `runtest` alias, and dune exposes NO per-test name filter (unlike `cargo test <name>`), so
-- there is no clean way to run one `let test_… ()` in isolation from the CLI. This module therefore
-- offers what dune CAN scope: the whole suite (`:LvimLang test`, in tasks.lua) and the test under the
-- cursor SCOPED TO ITS DIRECTORY — `dune runtest <dir>` for the directory owning the file — which is
-- the finest granularity dune gives without inventing a per-framework kludge. The enclosing test
-- binding's name is found with treesitter only to name the run. All through core.runner → lvim-tasks
-- (Test group, OCaml matcher). Richer per-test discovery lives in the lvim-test adapter.
--
---@module "lvim-lang.providers.ocaml.test"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")
local tasks = require("lvim-lang.providers.ocaml.tasks")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The dune project root for a buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "dune-project", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `dune <argv…>` for a root through lvim-tasks (Test group, OCaml matcher).
---@param root string
---@param argv string[]
---@param name string
---@return nil
local function run_dune(root, argv, name)
    local dune = toolchain.resolve("ocaml", "dune", root) or "dune"
    local cmd = { dune }
    vim.list_extend(cmd, argv)
    runner.run("ocaml", { name = name, cmd = cmd, cwd = root, group = "Test", matcher = tasks.matcher() })
end

--- The name of the `let …` binding enclosing the cursor (treesitter), or nil. Only used to LABEL the
--- run — dune cannot filter by it. Walks up to a `value_definition` and reads its binding's pattern.
---@param bufnr integer
---@return string|nil
local function enclosing_binding(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return nil
    end
    while node do
        if node:type() == "value_definition" then
            for child in node:iter_children() do
                if child:type() == "let_binding" then
                    local pat = child:field("pattern")[1]
                    return pat and vim.treesitter.get_node_text(pat, bufnr) or nil
                end
            end
        end
        node = node:parent()
    end
    return nil
end

--- `:LvimLang test-func` — run the tests in the DIRECTORY of the file under the cursor
--- (`dune runtest <dir>`) — the finest scope dune supports (it has no per-test filter). Notifies that
--- the whole directory's tests run, naming the enclosing binding when one is found.
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local bufnr = ctx.bufnr or vim.api.nvim_get_current_buf()
    local root = ctx.root or root_of(bufnr)
    local file = vim.api.nvim_buf_get_name(bufnr)
    if file == "" then
        vim.notify("lvim-lang: no file — open a test file to run it", vim.log.levels.WARN, TITLE)
        return
    end
    -- The file's directory, relative to the project root (dune's runtest scope is a dir subtree).
    local dir = vim.fs.dirname(file)
    local rel = dir
    if vim.startswith(dir, root) then
        rel = dir:sub(#root + 2) -- strip "<root>/"
        if rel == "" then
            rel = "."
        end
    end
    local name = enclosing_binding(bufnr)
    vim.notify(
        ("lvim-lang: dune has no per-test filter — running the whole `%s` test directory%s"):format(
            rel,
            name and (" (near `" .. name .. "`)") or ""
        ),
        vim.log.levels.INFO,
        TITLE
    )
    run_dune(root, { "runtest", rel }, "dune runtest " .. rel)
end

return M
