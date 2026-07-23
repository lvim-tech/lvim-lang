-- lvim-lang.providers.cpp.tasks: build / run / test / configure, run through lvim-tasks.
-- C/C++ has no single build system, so every command DETECTS the project shape at the root and
-- dispatches accordingly (first match wins):
--   * CMakeLists.txt → CMake: configure into `build/`, `cmake --build build`, `ctest`.
--   * Makefile       → Make:  `make`, `make test`, `make run`.
--   * neither        → single file: compile the buffer with the resolved compiler (`cc`/`c++`) into
--                      the lvim-lang cache dir, and run the produced binary.
-- Everything goes through core.runner → lvim-tasks with the `gcc` problem matcher (gcc / clang /
-- clang-tidy all emit `file:line:col: message`), so diagnostics land in the quickfix list.
--
---@module "lvim-lang.providers.cpp.tasks"

local config = require("lvim-lang.config")
local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The cpp config block.
---@return table
local function opts()
    return config.providers.cpp or {}
end

--- The build directory NAME for CMake output (config.build_dir, default "build").
---@return string
local function build_dir()
    return opts().build_dir or "build"
end

--- Resolve the C/C++ project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "compile_commands.json", "CMakeLists.txt", "Makefile", ".clangd", ".git" })
            or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- The build system that owns a root: "cmake" (CMakeLists.txt) → "make" (a Makefile) → "single".
---@param root string
---@return "cmake"|"make"|"single"
local function build_system(root)
    if vim.fn.filereadable(root .. "/CMakeLists.txt") == 1 then
        return "cmake"
    end
    for _, mk in ipairs({ "Makefile", "makefile", "GNUmakefile" }) do
        if vim.fn.filereadable(root .. "/" .. mk) == 1 then
            return "make"
        end
    end
    return "single"
end

--- The compiler for the current buffer: `c++` for a C++/Obj-C++ file, `cc` for C/Obj-C. Resolved
--- through the toolchain (explicit path → PATH).
---@param root string
---@return string
local function compiler(root)
    local ft = vim.bo[vim.api.nvim_get_current_buf()].filetype
    local tool = (ft == "cpp" or ft == "objcpp") and "c++" or "cc"
    return toolchain.resolve("cpp", tool, root) or tool
end

--- Run `cmake <argv…>` for a root through lvim-tasks (with the `gcc` matcher).
---@param root string
---@param argv string[]
---@param name string
---@param group string
---@param hooks? table
---@return nil
local function run_cmake(root, argv, name, group, hooks)
    local cmake = toolchain.resolve("cpp", "cmake", root) or "cmake"
    local cmd = { cmake }
    vim.list_extend(cmd, argv)
    runner.run("cpp", { name = name, cmd = cmd, cwd = root, group = group, matcher = "gcc", hooks = hooks })
end

--- Run `make <argv…>` for a root through lvim-tasks (with the `gcc` matcher).
---@param root string
---@param argv string[]
---@param name string
---@param group string
---@return nil
local function run_make(root, argv, name, group)
    local make = toolchain.resolve("cpp", "make", root) or "make"
    local cmd = { make }
    vim.list_extend(cmd, argv)
    runner.run("cpp", { name = name, cmd = cmd, cwd = root, group = group, matcher = "gcc" })
end

--- `:LvimLang configure [args]` — CMake configure into `build/`
--- (`cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`). Only meaningful for a CMake project.
---@param args string[]
---@param ctx table
---@return nil
function M.configure(args, ctx)
    local root = ctx.root or resolve_root()
    if build_system(root) ~= "cmake" then
        vim.notify("lvim-lang: no CMakeLists.txt — nothing to configure", vim.log.levels.INFO, TITLE)
        return
    end
    local argv = { "-S", ".", "-B", build_dir(), "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON" }
    vim.list_extend(argv, args)
    run_cmake(root, argv, "cmake configure", "Build")
end

--- `:LvimLang build [args]` — build the project. CMake: `cmake --build build` (configuring first
--- when the build tree has no cache, chained on exit). Make: `make`. Single file: compile the buffer
--- with the resolved compiler into the cache dir.
---@param args string[]
---@param ctx table
---@return nil
function M.build(args, ctx)
    local root = ctx.root or resolve_root()
    local sys = build_system(root)
    if sys == "cmake" then
        local dir = build_dir()
        local function do_build()
            local argv = { "--build", dir }
            vim.list_extend(argv, args)
            run_cmake(root, argv, "cmake build", "Build")
        end
        -- First build in a fresh checkout: configure (generate the build tree) then build. Chaining
        -- through the task's on_exit is the proper sequencing seam — not a post-hoc patch.
        if vim.fn.filereadable(root .. "/" .. dir .. "/CMakeCache.txt") ~= 1 then
            run_cmake(
                root,
                { "-S", ".", "-B", dir, "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON" },
                "cmake configure",
                "Build",
                {
                    on_exit = function(task)
                        if (task and task.exit_code or 0) == 0 then
                            vim.schedule(do_build)
                        end
                    end,
                }
            )
        else
            do_build()
        end
    elseif sys == "make" then
        run_make(root, args, "make", "Build")
    else
        M.build_single(args, ctx)
    end
end

--- Compile the current buffer's single file with the resolved compiler into the cache dir; returns
--- the output binary path (for build-and-run). Only for the single-file (no build system) case.
---@param args string[]
---@param ctx table
---@return string|nil out
function M.build_single(args, ctx)
    local buf = ctx.bufnr or vim.api.nvim_get_current_buf()
    local file = vim.api.nvim_buf_get_name(buf)
    if file == "" then
        vim.notify("lvim-lang: no file to compile", vim.log.levels.WARN, TITLE)
        return nil
    end
    local root = ctx.root or resolve_root()
    local cache = vim.fs.normalize(vim.fn.stdpath("cache") .. "/lvim-lang")
    if vim.fn.isdirectory(cache) == 0 then
        pcall(vim.fn.mkdir, cache, "p")
    end
    local out = cache .. "/" .. vim.fn.fnamemodify(file, ":t:r")
    local cmd = { compiler(root), file, "-o", out }
    vim.list_extend(cmd, args)
    runner.run("cpp", {
        name = "compile " .. vim.fs.basename(file),
        cmd = cmd,
        cwd = vim.fs.dirname(file),
        group = "Build",
        matcher = "gcc",
    })
    return out
end

--- `:LvimLang run [args]` — run the built program. A run config (`.lvim/lang/run.lua`) supplies the
--- program path (relative to the root), args and env; otherwise: CMake/Make → prompt for the binary
--- under `build/`; single file → compile the buffer and run the produced binary.
---@param args string[]
---@param ctx table
---@return nil
function M.run(args, ctx)
    local root = ctx.root or resolve_root()
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.program then
        local program = rc.program
        if not program:match("^/") then
            program = root .. "/" .. program
        end
        local cmd = { program }
        vim.list_extend(cmd, rc.args or {})
        vim.list_extend(cmd, args)
        runner.run("cpp", {
            name = "run " .. (rc.name or vim.fs.basename(program)),
            cmd = cmd,
            cwd = rc.cwd or root,
            env = rc.env,
            group = "Run",
            matcher = "gcc",
        })
        return
    end
    local sys = build_system(root)
    if sys == "single" then
        -- No build system → compile-and-run the buffer (build then execute the cache binary).
        local buf = ctx.bufnr or vim.api.nvim_get_current_buf()
        local file = vim.api.nvim_buf_get_name(buf)
        if file == "" then
            return
        end
        local cache = vim.fs.normalize(vim.fn.stdpath("cache") .. "/lvim-lang")
        if vim.fn.isdirectory(cache) == 0 then
            pcall(vim.fn.mkdir, cache, "p")
        end
        local out = cache .. "/" .. vim.fn.fnamemodify(file, ":t:r")
        local cc = compiler(root)
        local build = { cc, file, "-o", out }
        runner.run("cpp", {
            name = "build & run " .. vim.fs.basename(file),
            cmd = build,
            cwd = vim.fs.dirname(file),
            group = "Run",
            matcher = "gcc",
            hooks = {
                on_exit = function(task)
                    if (task and task.exit_code or 0) == 0 then
                        vim.schedule(function()
                            runner.run("cpp", {
                                name = "run " .. vim.fs.basename(out),
                                cmd = { out },
                                cwd = vim.fs.dirname(file),
                                group = "Run",
                            })
                        end)
                    end
                end,
            },
        })
        return
    end
    -- CMake / Make: prompt for the executable under the build dir (native cmdline input, as the DAP
    -- launch prompt does). A run config removes the prompt by supplying `program`.
    local base = sys == "cmake" and (root .. "/" .. build_dir() .. "/") or (root .. "/")
    local program = vim.fn.input("Path to binary: ", base, "file")
    if not program or program == "" then
        return
    end
    local cmd = { program }
    vim.list_extend(cmd, args)
    runner.run(
        "cpp",
        { name = "run " .. vim.fs.basename(program), cmd = cmd, cwd = root, group = "Run", matcher = "gcc" }
    )
end

--- `:LvimLang test [args]` — run the project's tests. CMake → `ctest --output-on-failure` in the
--- build dir. Make → `make test`. Single file → nothing sensible.
---@param args string[]
---@param ctx table
---@return nil
function M.test(args, ctx)
    local root = ctx.root or resolve_root()
    local sys = build_system(root)
    if sys == "cmake" then
        local ctest = opts().ctest_path or "ctest"
        local cmd = { ctest, "--test-dir", build_dir(), "--output-on-failure" }
        vim.list_extend(cmd, args)
        runner.run("cpp", { name = "ctest", cmd = cmd, cwd = root, group = "Test", matcher = "gcc" })
    elseif sys == "make" then
        run_make(root, vim.list_extend({ "test" }, args), "make test", "Test")
    else
        vim.notify("lvim-lang: no CMake/Make test target for a single file", vim.log.levels.INFO, TITLE)
    end
end

--- The buffer's project root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
