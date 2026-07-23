-- lvim-lang.providers.cpp: the C / C++ provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). One provider covers the whole C-family
-- (c / cpp / objc / objcpp); a single LSP server — clangd — attaches to all of them, formats natively
-- (clang-format) and lints inline (`--clang-tidy`). Because clangd owns formatting + linting, the
-- default efm formatter AND linter are `false` (like gopls/rust-analyzer); the catalog still OFFERS
-- clang-format (formatter) and clang-tidy (linter) as efm alternatives a user can select.
--
-- C/C++ has no version manager (system compilers) and no universal package manager (conan/vcpkg are
-- out of scope), so there is no version-manager seam and no deps module. Tasks DETECT the build
-- system per project (CMake / Make / single file) at run time — see providers.cpp.tasks.
--
---@module "lvim-lang.providers.cpp"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.core.toolchain")

-- Shared catalog entries, reused across every C-family filetype (clang-format / clang-tidy handle
-- c / cpp / objc / objcpp uniformly, and the debuggers are language-agnostic). Kept as locals so the
-- per-ft blocks below stay readable instead of repeating the same tables four times.
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
        linters = { ["clang-tidy"] = vim.deepcopy(CLANG_TIDY) },
        debuggers = vim.deepcopy(DEBUGGERS),
        -- clangd formats (clang-format) and lints (`--clang-tidy`) natively, so no separate efm tool
        -- runs by default; codelldb is the default debugger.
        defaults = { formatter = false, linter = false, debugger = "codelldb" },
    }
end

-- Per-language defaults, merged into config.providers.cpp at registration (users override via
-- setup({ providers = { cpp = { … } } })).
---@type table
local DEFAULTS = {
    -- Explicit binary paths; when set each wins over every other resolution strategy. No version
    -- manager: C/C++ compilers are system-installed.
    clangd_path = nil,
    clang_format_path = nil,
    clang_tidy_path = nil,
    cmake_path = nil,
    make_path = nil,
    cc_path = nil, -- the C compiler (default: `cc` on PATH)
    cxx_path = nil, -- the C++ compiler (default: `c++` on PATH)
    ctest_path = nil, -- the test driver (default: `ctest` on PATH)
    codelldb_path = nil,
    cpptools_path = nil, -- the cpptools debug adapter (OpenDebugAD7)

    -- The CMake build directory (relative to the project root). Used by build / run / test /
    -- configure / compile-commands.
    build_dir = "build",

    -- LSP server catalog. clangd is the single server for the whole C-family. It is configured
    -- through COMMAND-LINE FLAGS (not workspace settings); `flags` is the ordered flag list the
    -- server config passes as `cmd` after the resolved clangd binary.
    lsp = {
        servers = {
            clangd = {
                mason = "clangd",
                filetypes = { "c", "cpp", "objc", "objcpp" },
                role = "types", -- completion / hover / definition / rename / inlay hints / format
                flags = {
                    "--background-index", -- index the whole project in the background
                    "--clang-tidy", -- inline clang-tidy diagnostics (no separate linter needed)
                    "--header-insertion=iwyu", -- include-what-you-use header insertion
                    "--completion-style=detailed", -- detailed completion items
                    "--function-arg-placeholders=true", -- placeholders for function-call arguments (NB: this
                    -- clangd build rejects the bare flag — "requires a value!" — so the `=true` is mandatory)
                },
                -- clangd initializationOptions (empty by default; overridable). settings is unused —
                -- clangd is configured via flags + a project `.clangd` file.
                init_options = {},
                settings = {},
            },
        },
        default = "clangd",
    },

    -- Per-filetype formatter / linter / debugger catalog + selection. Every C-family filetype shares
    -- the same catalog (clang-format / clang-tidy / codelldb / cpptools); the defaults are false for
    -- formatter + linter because clangd does both natively (a user may still select clang-format /
    -- clang-tidy through efm here).
    ft = {
        c = ft_block(),
        cpp = ft_block(),
        objc = ft_block(),
        objcpp = ft_block(),
    },

    -- Statusline / picker icons (Nerd Font, single-width, all configurable).
    icons = {
        statusline = "󰙲", -- the C++ marker in the statusline segment
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        configure = "󱁤", -- cmake configure row
    },
}

--- Health section for :checkhealth lvim-lang: report whether the C/C++ toolchain resolves for the
--- current working directory, and at what version.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."
    -- clangd is the LSP; a compiler (cc/c++) is needed to build; the clang tools + cmake are optional.
    local report = {
        { tool = "clangd", level = "warn", hint = "install it via the mason registry (:LvimInstaller)" },
        { tool = "cc", level = "warn", hint = "install a C compiler (gcc / clang)" },
        { tool = "c++", level = "warn", hint = "install a C++ compiler (g++ / clang++)" },
        { tool = "cmake", level = "info", hint = "install CMake for CMake projects" },
        { tool = "clang-format", level = "info", hint = "the mason registry (clangd formats natively too)" },
        { tool = "clang-tidy", level = "info", hint = "the mason registry (clangd lints inline too)" },
    }
    for _, r in ipairs(report) do
        local path, reason = toolchain.resolve("cpp", r.tool, root)
        if path then
            local ver = toolchain.version("cpp", r.tool, root)
            h.ok(("%s: %s%s"):format(r.tool, path, ver and ("  (" .. ver .. ")") or ""))
        elseif r.level == "warn" then
            h.warn(("%s not found — %s"):format(r.tool, r.hint))
        else
            h.info(("%s not found — %s"):format(r.tool, r.hint))
        end
    end
end

--- Statusline segment for a root: the C++ marker + the active run config (if any).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.cpp and config.providers.cpp.icons) or {}
    local parts = { ic.statusline or "" }
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
    name = "cpp",
    filetypes = { "c", "cpp", "objc", "objcpp" },
    root_patterns = { "compile_commands.json", "CMakeLists.txt", "Makefile", ".clangd", ".git" },
    statusline = statusline,
    toolchain = require("lvim-lang.providers.cpp.toolchain"),
    commands = require("lvim-lang.providers.cpp.commands"),
    --- Surfaced at activation + in :checkhealth: clangd resolves symbols accurately only with a
    --- compilation database — informational, since clangd still runs on heuristic flags without one.
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
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
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
