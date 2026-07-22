-- lvim-lang.providers.go.toolchain: the Go toolchain spec.
-- Resolution order for `go` (first executable wins): an explicit config.go_path → a user
-- lookup command → a version-manager (mise/asdf) resolution honouring the project's pinned
-- version → PATH. `gopls` and `dlv` are Go-installed binaries: an explicit path → the
-- `go env GOBIN` / `GOPATH/bin` directory (where `go install` drops them) → PATH. Detection
-- only — nothing is installed here (missing tools come from the mason registry via the
-- installer). NB: Go CLIs use the `version` SUBCOMMAND, not `--version`.
--
---@module "lvim-lang.providers.go.toolchain"

local config = require("lvim-lang.config")

--- The go config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.go or {}
end

--- Run the user's `go_lookup_cmd` and take its first non-empty line as the go path.
---@return string|nil
local function lookup_go()
    local cmd = opts().go_lookup_cmd
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

--- Resolve `go` through the configured version manager (mise/asdf), honouring the project's
--- pinned version for `root`. `version_manager` may be a manager name ("mise"|"asdf"), false to
--- disable, or a function(root) -> path|nil for a custom seam. Default: try mise then asdf.
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
    -- `<mgr> which go` prints the resolved binary for the directory's pinned toolchain.
    local managers = type(vm) == "string" and { vm } or { "mise", "asdf" }
    for _, mgr in ipairs(managers) do
        if vim.fn.executable(mgr) == 1 then
            local out = vim.fn.systemlist({ mgr, "which", "go" })
            if vim.v.shell_error == 0 and type(out) == "table" and out[1] then
                local path = vim.trim(out[1])
                if path ~= "" and vim.fn.executable(path) == 1 then
                    return path
                end
            end
        end
    end
    return nil
end

--- The directory `go install` drops binaries into: `go env GOBIN`, else `go env GOPATH`/bin.
--- Resolved against the project root so a version-managed toolchain reports its own paths.
---@param root string
---@return string|nil
local function go_bin_dir(root)
    local go = require("lvim-lang.core.toolchain").resolve("go", "go", root)
    if not go then
        return nil
    end
    local function go_env(key)
        local out = vim.system({ go, "env", key }, { cwd = root, text = true }):wait()
        if out.code ~= 0 then
            return nil
        end
        local v = vim.trim(out.stdout or "")
        return v ~= "" and v or nil
    end
    local gobin = go_env("GOBIN")
    if gobin then
        return gobin
    end
    local gopath = go_env("GOPATH")
    return gopath and vim.fs.joinpath(gopath, "bin") or nil
end

--- Build a "path" strategy resolver for a Go-installed tool (`gopls`/`dlv`): the binary inside
--- the resolved `go install` bin directory, or nil.
---@param bin string
---@return fun(root: string): string|nil
local function in_go_bin(bin)
    return function(root)
        local dir = go_bin_dir(root)
        if not dir then
            return nil
        end
        local path = vim.fs.joinpath(dir, bin)
        return vim.fn.executable(path) == 1 and path or nil
    end
end

---@type LvimLangToolchainSpec
return {
    tools = {
        go = {
            {
                kind = "path",
                value = function()
                    return opts().go_path
                end,
            },
            { kind = "path", value = lookup_go },
            { kind = "path", value = via_version_manager },
            { kind = "which", value = "go" },
        },
        gopls = {
            {
                kind = "path",
                value = function()
                    return opts().gopls_path
                end,
            },
            { kind = "path", value = in_go_bin("gopls") },
            { kind = "which", value = "gopls" },
        },
        dlv = {
            {
                kind = "path",
                value = function()
                    return opts().dlv_path
                end,
            },
            { kind = "path", value = in_go_bin("dlv") },
            { kind = "which", value = "dlv" },
        },
    },

    --- `<bin> version` — first NON-EMPTY line, trimmed. Go CLIs (go/gopls/dlv) all use the
    --- `version` subcommand (not `--version`), and may prefix a blank/progress line.
    ---@param bin string
    ---@return string|nil
    version = function(bin)
        local out = vim.fn.systemlist({ bin, "version" })
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
