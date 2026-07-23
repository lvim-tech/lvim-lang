-- lvim-lang.providers.haskell.buildtool: detect the project's build tool and its invocation.
-- Haskell projects are driven by either Stack or Cabal; every runnable action (build / run / test /
-- deps) has to pick the right one and the right binary. Detection walks the project markers at the
-- resolved root: a `stack.yaml` → Stack; a `cabal.project` or any `*.cabal` package file → Cabal.
-- Stack is checked FIRST so a project that ships both (a `stack.yaml` beside its `.cabal`) prefers
-- Stack, the tool the author committed to. The binary itself is resolved per project through
-- core.toolchain by the callers (tasks / test / deps), so a version-managed cabal/stack wins over PATH.
-- Shared by tasks / test / deps so the three never disagree on the tool.
--
---@module "lvim-lang.providers.haskell.buildtool"

local M = {}

-- The fixed project-root markers (a `*.cabal` package file is matched separately, since vim.fs.root's
-- string-list form cannot glob). Shared by every Haskell module's root resolution.
---@type string[]
M.ROOT_PATTERNS = { "stack.yaml", "cabal.project", "package.yaml", ".git" }

--- Resolve the Haskell project root for a buffer: the nearest ancestor holding a fixed marker OR any
--- `*.cabal` file (a function marker catches the cabal package file the string list cannot), else the
--- buffer file's directory, else cwd. Shared by tasks / test / deps / dap so they agree on the root.
---@param bufnr integer
---@return string
function M.root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        local found = vim.fs.root(bufnr, function(fname)
            if fname:match("%.cabal$") then
                return true
            end
            for _, m in ipairs(M.ROOT_PATTERNS) do
                if fname == m then
                    return true
                end
            end
            return false
        end)
        return found or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Is `root/name` a readable file?
---@param root string
---@param name string
---@return boolean
local function has(root, name)
    return vim.fn.filereadable(vim.fs.joinpath(root, name)) == 1
end

--- Does `root` contain any `*.cabal` package description file?
---@param root string
---@return boolean
local function has_cabal_file(root)
    return #vim.fn.glob(vim.fs.joinpath(root, "*.cabal"), true, true) > 0
end

--- The build tool for a root: "stack" (a `stack.yaml`) → "cabal" (a `cabal.project` / `*.cabal`) →
--- nil when neither is present. Stack is checked first so a polyglot project with both prefers Stack.
---@param root string
---@return "stack"|"cabal"|nil
function M.detect(root)
    if has(root, "stack.yaml") then
        return "stack"
    end
    if has(root, "cabal.project") or has_cabal_file(root) then
        return "cabal"
    end
    return nil
end

--- The leading argv for a tool at `root`: the binary resolved per project through core.toolchain
--- (a version-managed / GHCup cabal|stack honoured), else the bare tool name for lvim-tasks to find
--- on PATH at run time.
---@param tool "stack"|"cabal"
---@param root string
---@return string[]
function M.base(tool, root)
    local bin = require("lvim-lang.core.toolchain").resolve("haskell", tool, root)
    return { (bin and bin ~= "") and bin or tool }
end

return M
