-- lvim-lang.providers.cpp.toolchain: the C / C++ toolchain spec.
-- C/C++ has NO version manager (the compilers are system-installed), so resolution for every tool
-- is the same short ladder (first executable wins): an explicit config path → the mason bin dir
-- (where lvim-installer drops clangd / clang-format / clang-tidy) → PATH. The compilers (`cc` /
-- `c++`) and the build drivers (`cmake` / `make`) are never mason packages — they come from PATH —
-- but still honour an explicit `<tool>_path`. Detection only: nothing is installed here (missing
-- clangd/clang-format/clang-tidy come from the mason registry through the installer).
--
---@module "lvim-lang.providers.cpp.toolchain"

local config = require("lvim-lang.config")

--- The cpp config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.cpp or {}
end

--- Build a resolver that returns an explicit config path for `key` (e.g. "clangd_path"), or nil.
---@param key string
---@return fun(): string|nil
local function explicit(key)
    return function()
        return opts()[key]
    end
end

--- The `bin` inside the resolved mason bin dir, if installed there (lvim-pkg owns the path — the
--- same dir the installer writes clangd / clang-format / clang-tidy into). nil when unavailable.
---@param bin string
---@return fun(): string|nil
local function in_mason(bin)
    return function()
        local ok, pkg = pcall(require, "lvim-pkg")
        if not ok or type(pkg.bin_dir) ~= "function" then
            return nil
        end
        local path = vim.fs.joinpath(pkg.bin_dir(), bin)
        return vim.fn.executable(path) == 1 and path or nil
    end
end

---@type LvimLangToolchainSpec
return {
    tools = {
        -- The language server + the clang tools: an explicit path → the mason bin → PATH.
        clangd = {
            { kind = "path", value = explicit("clangd_path") },
            { kind = "path", value = in_mason("clangd") },
            { kind = "which", value = "clangd" },
        },
        ["clang-format"] = {
            { kind = "path", value = explicit("clang_format_path") },
            { kind = "path", value = in_mason("clang-format") },
            { kind = "which", value = "clang-format" },
        },
        ["clang-tidy"] = {
            { kind = "path", value = explicit("clang_tidy_path") },
            { kind = "path", value = in_mason("clang-tidy") },
            { kind = "which", value = "clang-tidy" },
        },
        -- Build drivers + compilers: system tools (no mason), an explicit path → PATH.
        cmake = {
            { kind = "path", value = explicit("cmake_path") },
            { kind = "which", value = "cmake" },
        },
        make = {
            { kind = "path", value = explicit("make_path") },
            { kind = "which", value = "make" },
        },
        cc = {
            { kind = "path", value = explicit("cc_path") },
            { kind = "which", value = "cc" },
        },
        ["c++"] = {
            { kind = "path", value = explicit("cxx_path") },
            { kind = "which", value = "c++" },
        },
    },

    --- `<bin> --version` — first NON-EMPTY line, trimmed. clangd / clang-format / clang-tidy / cmake /
    --- cc / c++ all accept `--version` and print the version on the first line.
    ---@param bin string
    ---@return string|nil
    version = function(bin)
        local out = vim.fn.systemlist({ bin, "--version" })
        if vim.v.shell_error ~= 0 or type(out) ~= "table" then
            return nil
        end
        for _, line in ipairs(out) do
            local trimmed = vim.trim(line)
            if trimmed ~= "" then
                return trimmed
            end
        end
        return nil
    end,
}
