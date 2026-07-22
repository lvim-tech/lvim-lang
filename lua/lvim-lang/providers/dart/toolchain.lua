-- lvim-lang.providers.dart.toolchain: the Dart/Flutter toolchain spec.
-- Resolution order for `flutter` (first executable wins): an explicit config.flutter_path → a
-- user lookup command → an FVM-pinned SDK (<root>/.fvm/flutter_sdk) → PATH. `dart` mirrors it,
-- and additionally derives from the resolved flutter SDK (dart lives beside flutter in the SDK
-- bin dir), so a project that only pins Flutter still gets the matching Dart. Detection only —
-- nothing is installed here.
--
---@module "lvim-lang.providers.dart.toolchain"

local config = require("lvim-lang.config")

--- The dart config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.dart or {}
end

--- FVM-pinned SDK binary for a root, if the `.fvm/flutter_sdk` symlink exists.
---@param root string
---@param bin string  "flutter" | "dart"
---@return string|nil
local function fvm_bin(root, bin)
    if opts().fvm == false then
        return nil
    end
    local path = table.concat({ root, ".fvm", "flutter_sdk", "bin", bin }, "/")
    return vim.fn.executable(path) == 1 and path or nil
end

--- Run the user's `flutter_lookup_cmd` and take its first output line as the flutter path.
---@return string|nil
local function lookup_flutter()
    local cmd = opts().flutter_lookup_cmd
    if type(cmd) ~= "string" or cmd == "" then
        return nil
    end
    local out = vim.fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 or type(out) ~= "table" or not out[1] then
        return nil
    end
    return vim.trim(out[1])
end

--- The `dart` binary that sits next to the resolved `flutter` in the same SDK bin dir.
---@param root string
---@return string|nil
local function dart_beside_flutter(root)
    local flutter = require("lvim-lang.core.toolchain").resolve("dart", "flutter", root)
    if not flutter then
        return nil
    end
    local dart = vim.fs.joinpath(vim.fs.dirname(flutter), "dart")
    return vim.fn.executable(dart) == 1 and dart or nil
end

---@type LvimLangToolchainSpec
return {
    tools = {
        flutter = {
            {
                kind = "path",
                value = function()
                    return opts().flutter_path
                end,
            },
            { kind = "path", value = lookup_flutter },
            {
                kind = "path",
                value = function(root)
                    return fvm_bin(root, "flutter")
                end,
            },
            { kind = "which", value = "flutter" },
        },
        dart = {
            {
                kind = "path",
                value = function()
                    return opts().dart_path
                end,
            },
            {
                kind = "path",
                value = function(root)
                    return fvm_bin(root, "dart")
                end,
            },
            { kind = "path", value = dart_beside_flutter },
            { kind = "which", value = "dart" },
        },
    },

    --- `<bin> --version` — first NON-EMPTY line, trimmed. `flutter --version` can prefix its
    --- banner with a blank / progress line when the tool is cold (bootstrapping), so we skip
    --- leading empties instead of trusting `out[1]`.
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
