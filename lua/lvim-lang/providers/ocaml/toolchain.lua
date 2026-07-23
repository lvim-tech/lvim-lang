-- lvim-lang.providers.ocaml.toolchain: the OCaml toolchain spec.
-- OCaml toolchains are managed by opam (the OCaml package manager), which activates a per-project
-- "switch" — a self-contained set of compiler + libraries + tool binaries. Resolution for each tool
-- (first executable wins): an explicit config path → a user lookup command → the active opam switch
-- (`opam var bin` in the project root, which honours a local `_opam/` switch) → PATH. ocaml-lsp /
-- ocamlformat additionally fall back to the mason bin dir (a mason install of ocaml-lsp-server /
-- ocamlformat). Detection only — nothing is installed here.
--
---@module "lvim-lang.providers.ocaml.toolchain"

local config = require("lvim-lang.config")

--- The ocaml config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.ocaml or {}
end

--- Run the user's `ocaml_lookup_cmd` and take its first non-empty line as the ocaml path.
---@return string|nil
local function lookup_ocaml()
    local cmd = opts().ocaml_lookup_cmd
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

--- The `bin` directory of the opam switch active for `root` (`opam var bin`, run IN `root` so a
--- project-local `_opam/` switch wins over the global one), or nil when opam is unavailable.
---@param root string
---@return string|nil
local function opam_bin_dir(root)
    if vim.fn.executable("opam") ~= 1 then
        return nil
    end
    local out = vim.system({ "opam", "var", "bin" }, { cwd = root, text = true }):wait()
    if out.code ~= 0 then
        return nil
    end
    local dir = vim.trim(out.stdout or "")
    return (dir ~= "" and vim.fn.isdirectory(dir) == 1) and dir or nil
end

--- Resolve `tool` through the active opam switch for `root`. `version_manager` may be "opam", false
--- to disable, or a function(root, tool) -> path|nil. Default: try opam, then PATH.
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
    -- Only opam is supported as a named manager; any other value falls through to opam.
    local dir = opam_bin_dir(root)
    if not dir then
        return nil
    end
    local path = vim.fs.joinpath(dir, tool)
    return vim.fn.executable(path) == 1 and path or nil
end

--- Build a resolver that returns an explicit config path for `key` (e.g. "ocaml_path"), or nil.
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

--- The `bin` inside the resolved mason bin dir, if installed there (lvim-pkg owns the path — the same
--- dir the installer writes ocaml-lsp-server / ocamlformat into). nil when unavailable.
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
        ocaml = {
            { kind = "path", value = explicit("ocaml_path") },
            { kind = "path", value = lookup_ocaml },
            { kind = "path", value = vm("ocaml") },
            { kind = "which", value = "ocaml" },
        },
        dune = {
            { kind = "path", value = explicit("dune_path") },
            { kind = "path", value = vm("dune") },
            { kind = "which", value = "dune" },
        },
        -- The language server binary is `ocamllsp` (mason package `ocaml-lsp-server`).
        ["ocaml-lsp"] = {
            { kind = "path", value = explicit("ocaml_lsp_path") },
            { kind = "path", value = vm("ocamllsp") },
            { kind = "path", value = in_mason("ocamllsp") },
            { kind = "which", value = "ocamllsp" },
        },
        ocamlformat = {
            { kind = "path", value = explicit("ocamlformat_path") },
            { kind = "path", value = vm("ocamlformat") },
            { kind = "path", value = in_mason("ocamlformat") },
            { kind = "which", value = "ocamlformat" },
        },
        -- opam itself (for dependency commands + health); only ever on PATH.
        opam = {
            { kind = "which", value = "opam" },
        },
    },

    --- `<bin> --version` — first NON-EMPTY line, trimmed (ocaml / dune / ocamllsp / ocamlformat /
    --- opam all accept `--version` and print the version on the first line).
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
