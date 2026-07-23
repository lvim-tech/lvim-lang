-- lvim-lang.providers.cpp.codegen: generate compile_commands.json (the clangd compilation database).
-- clangd needs a compilation database to know each file's include paths / flags; without it, headers
-- and non-trivial projects mis-resolve. This produces one, per build system:
--   * CMake → `cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`, then symlink
--     `build/compile_commands.json` up to the root (clangd searches `build/` too, but the root link
--     is the convention `.clangd` and tooling expect).
--   * Make  → `bear -- make` (Bear intercepts the compiler calls and writes the database). Bear is a
--     mason package, installed on demand through core.ensure the first time it is needed.
-- One clean command (`:LvimLang compile-commands`); the run goes through lvim-tasks.
--
---@module "lvim-lang.providers.cpp.codegen"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")
local ensure = require("lvim-lang.core.ensure")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The cpp config block.
---@return table
local function opts()
    return config.providers.cpp or {}
end

--- Symlink `build/compile_commands.json` up to `<root>/compile_commands.json` (replacing any existing
--- link/file). Falls back to a copy when symlinks are unavailable.
---@param root string
---@param dir string  the build dir name
---@return nil
local function link_db(root, dir)
    local src = root .. "/" .. dir .. "/compile_commands.json"
    local dst = root .. "/compile_commands.json"
    if vim.fn.filereadable(src) ~= 1 then
        return
    end
    if vim.uv.fs_lstat(dst) then
        pcall(vim.uv.fs_unlink, dst)
    end
    local ok = pcall(vim.uv.fs_symlink, src, dst)
    if not ok then
        pcall(vim.fn.writefile, vim.fn.readfile(src), dst)
    end
    vim.notify("lvim-lang: compile_commands.json ready at the project root", vim.log.levels.INFO, TITLE)
end

--- `:LvimLang compile-commands` — generate the clangd compilation database for the project.
---@param _args string[]
---@param ctx table
---@return nil
function M.compile_commands(_args, ctx)
    local root = ctx.root or require("lvim-lang.providers.cpp.tasks").root()
    local dir = opts().build_dir or "build"
    if vim.fn.filereadable(root .. "/CMakeLists.txt") == 1 then
        local cmake = toolchain.resolve("cpp", "cmake", root) or "cmake"
        runner.run("cpp", {
            name = "compile_commands (cmake)",
            cmd = { cmake, "-S", ".", "-B", dir, "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON" },
            cwd = root,
            group = "Build",
            matcher = "gcc",
            hooks = {
                on_exit = function(task)
                    if (task and task.exit_code or 0) == 0 then
                        vim.schedule(function()
                            link_db(root, dir)
                        end)
                    end
                end,
            },
        })
        return
    end
    for _, mk in ipairs({ "Makefile", "makefile", "GNUmakefile" }) do
        if vim.fn.filereadable(root .. "/" .. mk) == 1 then
            local make = toolchain.resolve("cpp", "make", root) or "make"
            ensure.tool("bear", "bear", function(bear)
                runner.run("cpp", {
                    name = "compile_commands (bear)",
                    cmd = { bear, "--", make },
                    cwd = root,
                    group = "Build",
                    matcher = "gcc",
                })
            end)
            return
        end
    end
    vim.notify(
        "lvim-lang: no CMakeLists.txt / Makefile — cannot generate compile_commands.json",
        vim.log.levels.INFO,
        TITLE
    )
end

return M
