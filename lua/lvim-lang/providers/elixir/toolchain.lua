-- lvim-lang.providers.elixir.toolchain: the Elixir toolchain spec.
-- Elixir installs are almost always managed by a version manager (mise / asdf), and the project's
-- `.tool-versions` pins which one. Resolution order for `elixir` (first executable wins): an explicit
-- `elixir_path` → a user lookup command → the version manager (`<mgr> which elixir`, run in `root` so
-- the project pin wins) → PATH. `mix` and `iex` ship WITH elixir, so they resolve from the selected
-- elixir's bin dir first (tracking a version-managed install), then the version manager, then PATH.
-- The language servers (elixir-ls / lexical / next-ls) and the elixir-ls debug adapter are mason
-- packages: an explicit path → the mason bin → PATH. Detection only; nothing is installed here.
--
---@module "lvim-lang.providers.elixir.toolchain"

local config = require("lvim-lang.config")

--- The elixir config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.elixir or {}
end

--- Run the user's `elixir_lookup_cmd` and take its first non-empty line as the elixir path.
---@return string|nil
local function lookup_elixir()
    local cmd = opts().elixir_lookup_cmd
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

--- Resolve `tool` through the configured version manager, honouring the project's pin for `root`.
--- `version_manager` may be a name ("mise"|"asdf"), false to disable, or a function(root, tool).
--- Default: try mise then asdf (`<mgr> which <tool>`, run in `root` so `.tool-versions` wins).
---@param tool string
---@param root string
---@return string|nil
local function via_version_manager(tool, root)
    local vm = opts().version_manager
    if vm == false then
        return nil
    end
    if type(vm) == "function" then
        return vm(root, tool)
    end
    local managers = type(vm) == "string" and { vm } or { "mise", "asdf" }
    for _, mgr in ipairs(managers) do
        if vim.fn.executable(mgr) == 1 then
            local out = vim.system({ mgr, "which", tool }, { cwd = root, text = true }):wait()
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

--- Build a resolver that returns the explicit config path under `key` (e.g. "elixir_path"), or nil.
---@param key string
---@return fun(): string|nil
local function explicit(key)
    return function()
        return opts()[key]
    end
end

--- Build a version-manager resolver for `tool`.
---@param tool string
---@return fun(root: string): string|nil
local function vm(tool)
    return function(root)
        return via_version_manager(tool, root)
    end
end

--- Resolve a tool `bin` inside the selected elixir's bin directory (where `mix` / `iex` live beside
--- `elixir`): `<dirname(elixir)>/<bin>`, if executable. Tracks a version-managed elixir's own tools.
---@param bin string
---@return fun(root: string): string|nil
local function in_elixir_bin(bin)
    return function(root)
        local elixir = require("lvim-lang.core.toolchain").resolve("elixir", "elixir", root)
        if not elixir then
            return nil
        end
        local path = vim.fs.joinpath(vim.fs.dirname(elixir), bin)
        return vim.fn.executable(path) == 1 and path or nil
    end
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
        -- The runtime: config → lookup cmd → version manager (project pin) → PATH.
        elixir = {
            { kind = "path", value = explicit("elixir_path") },
            { kind = "path", value = lookup_elixir },
            { kind = "path", value = vm("elixir") },
            { kind = "which", value = "elixir" },
        },
        -- mix ships with elixir: config → the selected elixir's bin → version manager → PATH.
        mix = {
            { kind = "path", value = explicit("mix_path") },
            { kind = "path", value = in_elixir_bin("mix") },
            { kind = "path", value = vm("mix") },
            { kind = "which", value = "mix" },
        },
        -- iex ships with elixir: the selected elixir's bin → version manager → PATH.
        iex = {
            { kind = "path", value = in_elixir_bin("iex") },
            { kind = "path", value = vm("iex") },
            { kind = "which", value = "iex" },
        },
        -- The elixir-ls language server (a mason package): config → mason → PATH.
        ["elixir-ls"] = {
            { kind = "path", value = explicit("elixir_ls_path") },
            { kind = "path", value = in_mason("elixir-ls") },
            { kind = "which", value = "elixir-ls" },
        },
        -- lexical (the alternative server, a mason package): mason → PATH.
        lexical = {
            { kind = "path", value = in_mason("lexical") },
            { kind = "which", value = "lexical" },
        },
        -- next-ls (the alternative server, a mason package; its binary is `nextls`): mason → PATH.
        nextls = {
            { kind = "path", value = in_mason("nextls") },
            { kind = "which", value = "nextls" },
        },
        -- The elixir-ls debug adapter — ships INSIDE the elixir-ls mason package as a second binary
        -- (`elixir-ls-debugger`): config → mason → PATH.
        ["elixir-ls-debugger"] = {
            { kind = "path", value = explicit("elixir_ls_debugger_path") },
            { kind = "path", value = in_mason("elixir-ls-debugger") },
            { kind = "which", value = "elixir-ls-debugger" },
        },
    },

    --- Version string for a resolved tool. `elixir` / `iex` print the Erlang/OTP line FIRST, so the
    --- `Elixir …` / `IEx …` / `Mix …` line is preferred; otherwise the first non-empty line.
    ---@param bin string
    ---@return string|nil
    version = function(bin)
        local out = vim.fn.systemlist({ bin, "--version" })
        if vim.v.shell_error ~= 0 or type(out) ~= "table" then
            return nil
        end
        local first
        for _, line in ipairs(out) do
            local trimmed = vim.trim(line)
            if trimmed ~= "" then
                first = first or trimmed
                if trimmed:match("^Elixir ") or trimmed:match("^IEx ") or trimmed:match("^Mix ") then
                    return trimmed
                end
            end
        end
        return first
    end,
}
