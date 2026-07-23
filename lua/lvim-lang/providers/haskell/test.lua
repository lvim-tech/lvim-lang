-- lvim-lang.providers.haskell.test: hspec test running — the whole suite, the current file's suites,
-- and the describe/it example under the cursor. Haskell's dominant test framework, hspec, addresses
-- examples by a `/describe/context/it/` PATH and filters with `--match <path>`. The path under the
-- cursor is recovered from treesitter: walking the ancestors and reading each `describe "…"` /
-- `context "…"` / `it "…"` / `specify "…"` / `prop "…"` application's string label (matched on the
-- node's leading source, so it is robust to the grammar's exact node names and the `$`/`do` styles).
-- The whole-suite / file suites and the example run all go through core.runner → lvim-tasks (Test
-- group, `haskell` errorformat) under whichever build tool the project uses.
--
-- The hspec args reach the test executable differently per tool: Cabal's repeatable `--test-option=`
-- passes each value as its OWN argv (labels with spaces survive intact); Stack's `--test-arguments`
-- takes one string it word-splits, so a label containing spaces can mis-split there (a Stack
-- limitation, noted in the docs) — Cabal is the exact path.
--
---@module "lvim-lang.providers.haskell.test"

local runner = require("lvim-lang.core.runner")
local buildtool = require("lvim-lang.providers.haskell.buildtool")
local tasks = require("lvim-lang.providers.haskell.tasks")

local TITLE = { title = "lvim-lang" }

-- hspec's spec-tree combinators whose first string argument is a path segment.
---@type table<string, boolean>
local HSPEC_KW = {
    describe = true,
    context = true,
    it = true,
    specify = true,
    prop = true,
    fit = true,
    xit = true,
    fdescribe = true,
    xdescribe = true,
    fcontext = true,
    xcontext = true,
    fspecify = true,
    xspecify = true,
}

local M = {}

--- The hspec label a node's LEADING source declares (`describe "Foo"` → "Foo"), or nil. Reads the
--- node's first source line so it is independent of the tree-sitter-haskell node names and matches
--- both the `$`/`do` and braced styles.
---@param text string  the node's source text
---@return string|nil
local function label_of(text)
    local first = text:match("^[^\n]*") or ""
    local kw, str = first:match('^%s*(%a+)%s+"([^"]*)"')
    if kw and HSPEC_KW[kw] then
        return str
    end
    return nil
end

--- The `/describe/…/it/` path of the hspec example under the cursor (outermost → innermost), via
--- treesitter. Empty when the cursor is not inside an hspec example.
---@param bufnr integer
---@return string[]
local function lineage(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok or not node then
        return {}
    end
    local parts = {}
    while node do
        local label = label_of(vim.treesitter.get_node_text(node, bufnr))
        -- Walking innermost → outermost: prepend, skipping a consecutive duplicate (the same combinator
        -- can surface on several nested ancestor nodes).
        if label and parts[1] ~= label then
            table.insert(parts, 1, label)
        end
        node = node:parent()
    end
    return parts
end

--- The buffer's TOP-LEVEL `describe "…"` labels (those at the shallowest indentation), for running a
--- file's suites. A simple indentation scan — enough to select the module's root suites via `--match`.
---@param bufnr integer
---@return string[]
local function top_describes(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local found, min = {}, math.huge
    for _, l in ipairs(lines) do
        local indent, label = l:match('^(%s*)describe%s+"([^"]*)"')
        if label then
            found[#found + 1] = { #indent, label }
            if #indent < min then
                min = #indent
            end
        end
    end
    local out = {}
    for _, f in ipairs(found) do
        if f[1] == min then
            out[#out + 1] = f[2]
        end
    end
    return out
end

--- An hspec match pattern for a path (`{ "Math", "adds" }` → "/Math/adds/").
---@param parts string[]
---@return string
local function pattern_of(parts)
    return "/" .. table.concat(parts, "/") .. "/"
end

--- The build-tool argv tail that passes hspec `--match <pattern>` for each pattern to the test
--- executable. Cabal uses the repeatable `--test-option=` (each value its own argv — space-safe);
--- Stack uses the single `--test-arguments` string.
---@param tool "stack"|"cabal"
---@param patterns string[]
---@return string[]
local function filter_args(tool, patterns)
    if tool == "cabal" then
        local out = {}
        for _, p in ipairs(patterns) do
            out[#out + 1] = "--test-option=--match"
            out[#out + 1] = "--test-option=" .. p
        end
        return out
    end
    -- Stack: one whitespace-joined `--test-arguments` string.
    local pieces = {}
    for _, p in ipairs(patterns) do
        pieces[#pieces + 1] = "--match"
        pieces[#pieces + 1] = p
    end
    return { "--test-arguments", table.concat(pieces, " ") }
end

--- Run the build tool's `test` with hspec `--match` filters for `patterns`, at `root`, through
--- lvim-tasks (Test group, `haskell` errorformat).
---@param root string
---@param patterns string[]
---@param label string
---@return nil
local function run_filtered(root, patterns, label)
    local tool = buildtool.detect(root)
    if not tool then
        vim.notify("lvim-lang: no Stack or Cabal project found", vim.log.levels.WARN, TITLE)
        return
    end
    local cmd = buildtool.base(tool, root)
    cmd[#cmd + 1] = "test"
    vim.list_extend(cmd, filter_args(tool, patterns))
    runner.run("haskell", { name = label, cmd = cmd, cwd = root, group = "Test", matcher = tasks.efm() })
end

--- `:LvimLang test-func` — run the hspec example under the cursor (`--match "/describe/…/it/"`).
---@param _args string[]
---@param ctx table
---@return nil
function M.func(_args, ctx)
    local parts = lineage(ctx.bufnr)
    if #parts == 0 then
        vim.notify("lvim-lang: cursor is not inside an hspec describe/it example", vim.log.levels.WARN, TITLE)
        return
    end
    run_filtered(ctx.root or buildtool.root_of(ctx.bufnr), { pattern_of(parts) }, "test " .. pattern_of(parts))
end

--- `:LvimLang test-file` — run the current file's top-level hspec suites (`--match "/describe/"` for
--- each). Falls back to the whole suite when the buffer has no recognizable `describe` block.
---@param _args string[]
---@param ctx table
---@return nil
function M.file(_args, ctx)
    local root = ctx.root or buildtool.root_of(ctx.bufnr)
    local describes = top_describes(ctx.bufnr)
    if #describes == 0 then
        vim.notify(
            "lvim-lang: no top-level `describe` found — running the whole test suite",
            vim.log.levels.INFO,
            TITLE
        )
        M.suite(_args, ctx)
        return
    end
    local patterns = {}
    for _, d in ipairs(describes) do
        patterns[#patterns + 1] = pattern_of({ d })
    end
    run_filtered(root, patterns, "test file (" .. #describes .. " suite(s))")
end

--- Run the whole test suite (`stack test` / `cabal test`) — the fallback when no hspec filter applies.
---@param args string[]
---@param ctx table
---@return nil
function M.suite(args, ctx)
    tasks.test(args, ctx)
end

return M
