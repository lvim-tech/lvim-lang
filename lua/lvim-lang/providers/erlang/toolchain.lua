-- lvim-lang.providers.erlang.toolchain: the Erlang toolchain spec.
-- Erlang/OTP is the user's OWN runtime — usually managed by a version manager (mise / asdf / kerl)
-- and pinned per project through `.tool-versions`. Resolution order for `erl` (first executable
-- wins): an explicit `erl_path` → a user lookup command → the version manager (`mise/asdf which erl`,
-- honouring the project pin for `root`) → PATH. `rebar3` is the build tool: an explicit path → the
-- project-local escript (`<root>/rebar3`, how many projects vendor it) → PATH. erlang_ls (the LSP,
-- mason package `erlang-ls`, binary `erlang_ls`) and erlfmt (the formatter) fall back to the mason bin
-- when not on PATH. Detection only — nothing is installed here.
--
---@module "lvim-lang.providers.erlang.toolchain"

local config = require("lvim-lang.config")

--- The erlang config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.erlang or {}
end

--- Run the user's `erl_lookup_cmd` and take its first non-empty line as the `erl` path.
---@return string|nil
local function lookup_erl()
    local cmd = opts().erl_lookup_cmd
    if type(cmd) ~= "string" or cmd == "" then
        return nil
    end
    local out = vim.fn.systemlist(cmd)
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
end

--- Resolve `erl` through the configured version manager, honouring the project's pin for `root`.
--- `version_manager` may be a manager name ("mise"|"asdf"), false to disable, or a function(root) ->
--- path|nil. Default: try mise, then asdf (each `<mgr> which erl`, run in `root` so `.tool-versions`
--- wins). kerl has no resolver CLI (it is a shell installer), so a kerl-managed erl is found on PATH.
---@param root string
---@return string|nil
local function via_version_manager(root)
    local vm = opts().version_manager
    if vm == false then
        return nil
    end
    if type(vm) == "function" then
        return vm(root)
    end
    local managers = type(vm) == "string" and { vm } or { "mise", "asdf" }
    for _, mgr in ipairs(managers) do
        if vim.fn.executable(mgr) == 1 then
            local out = vim.system({ mgr, "which", "erl" }, { cwd = root, text = true }):wait()
            if out.code == 0 then
                local path = vim.trim(out.stdout or "")
                if path ~= "" and vim.fn.executable(path) == 1 then
                    return path
                end
            end
        end
    end
    return nil
end

--- Build a resolver that returns the explicit config path under `key` (e.g. "erl_path"), or nil.
---@param key string
---@return fun(): string|nil
local function explicit(key)
    return function()
        return opts()[key]
    end
end

--- Resolve the project-vendored rebar3 escript: `<root>/rebar3`, if executable (many Erlang projects
--- commit the rebar3 escript at the repo root so every checkout builds with the same version).
---@param root string
---@return string|nil
local function vendored_rebar3(root)
    local path = vim.fs.joinpath(root, "rebar3")
    return vim.fn.executable(path) == 1 and path or nil
end

--- Resolve a tool `bin` inside the mason bin directory (lvim-pkg), if installed there.
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
        -- The Erlang emulator: config → lookup cmd → version manager (project pin) → PATH.
        erl = {
            { kind = "path", value = explicit("erl_path") },
            { kind = "path", value = lookup_erl },
            { kind = "path", value = via_version_manager },
            { kind = "which", value = "erl" },
        },
        -- The build tool: config → the project-vendored escript → PATH.
        rebar3 = {
            { kind = "path", value = explicit("rebar3_path") },
            { kind = "path", value = vendored_rebar3 },
            { kind = "which", value = "rebar3" },
        },
        -- The language server (mason `erlang-ls`, binary `erlang_ls`): config → mason → PATH.
        erlang_ls = {
            { kind = "path", value = explicit("erlang_ls_path") },
            { kind = "path", value = in_mason("erlang_ls") },
            { kind = "which", value = "erlang_ls" },
        },
        -- The formatter (a mason package, also `rebar3 fmt` when the plugin is configured): config →
        -- mason → PATH.
        erlfmt = {
            { kind = "path", value = explicit("erlfmt_path") },
            { kind = "path", value = in_mason("erlfmt") },
            { kind = "which", value = "erlfmt" },
        },
    },

    --- The version string for a resolved tool. `erl` has no `--version` flag, so its OTP release is
    --- read out of the emulator (`erlang:system_info(otp_release)`); rebar3 / erlang_ls / erlfmt all
    --- accept `--version`. Returns the first non-empty trimmed line, or nil.
    ---@param bin string
    ---@return string|nil
    version = function(bin)
        local out
        if vim.fs.basename(bin) == "erl" then
            out = vim.fn.systemlist({
                bin,
                "-noshell",
                "-eval",
                'io:format("OTP ~s~n", [erlang:system_info(otp_release)]), halt().',
            })
        else
            out = vim.fn.systemlist({ bin, "--version" })
        end
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
