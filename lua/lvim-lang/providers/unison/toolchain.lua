-- lvim-lang.providers.unison.toolchain: the Unison toolchain spec.
-- Unison ships a SINGLE tool — `ucm` (the Unison Codebase Manager). Everything else (the LSP
-- server, the type-checker, the REPL, the codebase server) lives INSIDE a running `ucm`, so there
-- is nothing else to resolve here. Resolution order for `ucm` (first executable wins): an explicit
-- config.ucm_path → a user lookup command → PATH. Detection only — nothing is installed here (the
-- Unison LSP is not a mason package; it is served by a `ucm` the user launches themselves).
--
---@module "lvim-lang.providers.unison.toolchain"

local config = require("lvim-lang.config")

--- The unison config block (seeded by the provider's setup defaults).
---@return table
local function opts()
    return config.providers.unison or {}
end

--- Run the user's `ucm_lookup_cmd` and take its first non-empty line as the ucm path.
---@return string|nil
local function lookup_ucm()
    local cmd = opts().ucm_lookup_cmd
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

---@type LvimLangToolchainSpec
return {
    tools = {
        ucm = {
            {
                kind = "path",
                value = function()
                    return opts().ucm_path
                end,
            },
            { kind = "path", value = lookup_ucm },
            { kind = "which", value = "ucm" },
        },
    },

    --- `ucm --version` — first NON-EMPTY line, trimmed.
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
