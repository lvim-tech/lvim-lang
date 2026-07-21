-- lvim-lang.providers.dart.tasks: one-shot `flutter` CLI commands run through lvim-tasks.
-- clean / test / doctor / build are fire-and-collect commands (not the persistent daemon), so
-- they go through core.runner → lvim-tasks and land in its panel / history / dock with a sensible
-- display group. Extra command-line args are appended (e.g. `:LvimLang build apk --release`).
--
---@module "lvim-lang.providers.dart.tasks"

local toolchain = require("lvim-lang.core.toolchain")
local runner = require("lvim-lang.core.runner")

local M = {}

--- Resolve the pubspec project root for the current buffer (else cwd).
---@return string
local function resolve_root()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
        return vim.fs.root(buf, { "pubspec.yaml", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Run `flutter <argv…>` for a root through lvim-tasks.
---@param root string
---@param argv string[]
---@param name string
---@param group string
---@return nil
local function run_flutter(root, argv, name, group)
    local flutter = toolchain.resolve("dart", "flutter", root) or "flutter"
    local cmd = { flutter }
    vim.list_extend(cmd, argv)
    runner.run("dart", { name = name, cmd = cmd, cwd = root, group = group })
end

--- `:LvimLang clean` — `flutter clean`.
---@param _args string[]
---@param ctx table
---@return nil
function M.clean(_args, ctx)
    run_flutter(ctx.root, { "clean" }, "flutter clean", "Build")
end

--- `:LvimLang test [args]` — `flutter test`.
---@param args string[]
---@param ctx table
---@return nil
function M.test(args, ctx)
    local argv = { "test" }
    vim.list_extend(argv, args)
    run_flutter(ctx.root, argv, "flutter test", "Test")
end

--- `:LvimLang doctor` — `flutter doctor -v`.
---@param _args string[]
---@param ctx table
---@return nil
function M.doctor(_args, ctx)
    run_flutter(ctx.root, { "doctor", "-v" }, "flutter doctor", "Doctor")
end

-- Known `flutter build` targets (for completion).
M.build_targets = { "apk", "appbundle", "aar", "bundle", "ios", "ipa", "linux", "macos", "web", "windows" }

--- `:LvimLang build <target> [args]` — `flutter build <target>`.
---@param args string[]
---@param ctx table
---@return nil
function M.build(args, ctx)
    local target = args[1]
    if not target then
        vim.notify(
            "lvim-lang: usage — :LvimLang build <" .. table.concat(M.build_targets, "|") .. ">",
            vim.log.levels.INFO,
            { title = "lvim-lang" }
        )
        return
    end
    local argv = { "build" }
    vim.list_extend(argv, args)
    run_flutter(ctx.root, argv, "flutter build " .. target, "Build")
end

--- The buffer's project root (exposed so command wrappers share the resolution).
---@return string
function M.root()
    return resolve_root()
end

return M
