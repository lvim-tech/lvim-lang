-- lvim-lang.providers.cpp: the C / C++ provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes (c / cpp / objc / objcpp), the clangd catalog, the per-filetype tool catalog
-- (clang-format / clang-tidy formatters+linters, codelldb / cpptools debuggers), the toolchain, health
-- and statusline. C/C++ has NO version manager (system compilers) — the compiler / build-driver runtimes
-- declare `managers = {}` so they resolve explicit → PATH with no manager probing. This module then
-- EXTENDS the returned spec with the one thing pure data cannot express — the informational compilation-
-- database requirement (clangd resolves symbols accurately only with compile_commands.json) — plus the
-- build-system-detecting command surface (CMake / Make / single file — providers.cpp.commands / .tasks).
--
-- clangd formats (clang-format) + lints (`--clang-tidy`) natively, so the efm formatter/linter default
-- off. clangd keeps its bespoke servers/clangd.lua (it passes the `flags` list as the launch cmd).
--
---@module "lvim-lang.providers.cpp"

local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")

-- Shared catalog entries, reused across every C-family filetype (clang-format / clang-tidy handle
-- c / cpp / objc / objcpp uniformly; the debuggers are language-agnostic).
---@type table
local CLANG_FORMAT = {
    mason = "clang-format",
    efm = { formatCommand = "clang-format --assume-filename=${INPUT}", formatStdin = true },
}
---@type table
local CLANG_TIDY = {
    mason = "clang-tidy",
    efm = {
        lintCommand = "clang-tidy ${INPUT} --quiet",
        lintStdin = false,
        lintFormats = { "%f:%l:%c: %trror: %m", "%f:%l:%c: %tarning: %m", "%f:%l:%c: %tote: %m" },
        rootMarkers = { "compile_commands.json", ".clang-tidy" },
    },
}
-- cpplint: Google's style linter (opt-in; clangd's --clang-tidy diagnoses by default).
---@type table
local CPPLINT = {
    mason = "cpplint",
    efm = {
        lintCommand = "cpplint ${INPUT}",
        lintStdin = false,
        lintFormats = { "%f:%l: %m" },
    },
}
-- semgrep: cross-language static analysis (opt-in; needs `--config auto` / a ruleset).
---@type table
local SEMGREP = {
    mason = "semgrep",
    efm = {
        lintCommand = "semgrep scan --config auto --quiet --error --disable-version-check --gitlab-sast ${INPUT}",
        lintStdin = false,
        lintFormats = { "%f:%l:%c: %m" },
    },
}
---@type table<string, table>
local DEBUGGERS = {
    codelldb = { mason = "codelldb" },
    cpptools = { mason = "cpptools", bin = "OpenDebugAD7" },
}

--- The per-filetype catalog block shared by every C-family filetype (its own copy so a user can
--- override one filetype without touching the others).
---@return table
local function ft_block()
    return {
        formatters = { ["clang-format"] = vim.deepcopy(CLANG_FORMAT) },
        linters = {
            ["clang-tidy"] = vim.deepcopy(CLANG_TIDY),
            cpplint = vim.deepcopy(CPPLINT),
            semgrep = vim.deepcopy(SEMGREP),
        },
        debuggers = vim.deepcopy(DEBUGGERS),
        defaults = { formatter = false, linter = false, debugger = "codelldb" },
    }
end

---@type LvimLangSpecData
local DATA = {
    name = "cpp",
    filetypes = { "c", "cpp", "objc", "objcpp" },
    root_patterns = { "compile_commands.json", "CMakeLists.txt", "Makefile", ".clangd", ".git" },

    -- System compilers + build drivers — no version manager (`managers = {}` skips the probe), not surfaced
    -- as requirements (the compilation-database check below is the only one). Explicit paths via bin_paths.
    runtimes = {
        { bin = "cc", key = "cc", managers = {} },
        { bin = "c++", key = "c++", managers = {} },
        { bin = "cmake", key = "cmake", managers = {} },
        { bin = "make", key = "make", managers = {} },
        { bin = "ctest", key = "ctest", managers = {} },
    },

    lsp = {
        servers = {
            clangd = {
                mason = "clangd",
                filetypes = { "c", "cpp", "objc", "objcpp" },
                role = "types", -- completion / hover / definition / rename / inlay hints / format
                flags = {
                    "--background-index",
                    "--clang-tidy",
                    "--header-insertion=iwyu",
                    "--completion-style=detailed",
                    "--function-arg-placeholders=true",
                },
                init_options = {},
                settings = {},
            },
        },
        default = "clangd",
    },

    ft = {
        c = ft_block(),
        cpp = ft_block(),
        objc = ft_block(),
        objcpp = ft_block(),
    },

    icons = {
        statusline = "󰙲", -- the C++ marker in the statusline segment
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        configure = "󱁤", -- cmake configure row
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND ─────────────────────────────────────────────────────────────────────────────────────────

-- The CMake build directory (relative to the project root) — used by build / run / test / configure.
defaults.build_dir = "build"

-- Requirement: clangd resolves symbols accurately only with a compilation database — informational (it
-- still runs on heuristic flags without one).
spec.requirements = function(root)
    local have = vim.uv.fs_stat(root .. "/compile_commands.json") ~= nil
        or vim.uv.fs_stat(root .. "/build/compile_commands.json") ~= nil
        or vim.uv.fs_stat(root .. "/compile_flags.txt") ~= nil
    return {
        {
            label = "clangd compilation database",
            ok = have,
            detail = have and "compile_commands.json / compile_flags.txt found" or "none found",
            hint = "Generate compile_commands.json (cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON, or `bear -- make`) "
                .. "or add compile_flags.txt, so clangd knows your include paths and flags.",
            severity = "info",
        },
    }
end

spec.commands = require("lvim-lang.providers.cpp.commands")

registry.register(spec, defaults)

return spec
