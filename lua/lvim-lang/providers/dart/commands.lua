-- lvim-lang.providers.dart.commands: the Dart subcommands exposed under :LvimLang.
-- Only language-specific commands live here; generic ones (status, providers, toolchain) are
-- core subcommands in lvim-lang.commands. Custom dartls methods (super, reanalyze) go straight
-- to the attached client; `lsp restart` drives lvim-lsp's enable/disable. Grows per milestone.
--
---@module "lvim-lang.providers.dart.commands"

local toolchain = require("lvim-lang.core.toolchain")
local decorations = require("lvim-lang.core.decorations")
local runcfg = require("lvim-lang.core.runcfg")
local pub = require("lvim-lang.providers.dart.pub")
local tasks = require("lvim-lang.providers.dart.tasks")
local run = require("lvim-lang.providers.dart.run")
local devices = require("lvim-lang.providers.dart.devices")
local devtools = require("lvim-lang.providers.dart.devtools")
local vmservice = require("lvim-lang.providers.dart.vmservice")
local sdk = require("lvim-lang.providers.dart.sdk")
local ui = require("lvim-lang.core.ui")

local TITLE = { title = "lvim-lang" }

--- The dartls client attached to `bufnr`, or nil.
---@param bufnr integer
---@return vim.lsp.Client|nil
local function dart_client(bufnr)
    return vim.lsp.get_clients({ bufnr = bufnr, name = "dart" })[1]
end

--- Warn that dartls is not attached (shared by the LSP-backed commands).
---@return nil
local function no_client()
    vim.notify("lvim-lang: dartls is not attached to this buffer", vim.log.levels.WARN, TITLE)
end

--- `dart/textDocument/super` — jump to the super implementation/definition at the cursor.
---@param _args string[]
---@param ctx table  { provider, root, bufnr }
---@return nil
local function super(_args, ctx)
    local client = dart_client(ctx.bufnr)
    if not client then
        return no_client()
    end
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    -- custom dartls method — not in the built-in LSP method union
    ---@diagnostic disable-next-line: param-type-mismatch
    client:request("dart/textDocument/super", params, function(err, result)
        if err or not result then
            vim.notify("lvim-lang: no super found", vim.log.levels.INFO, TITLE)
            return
        end
        vim.lsp.util.show_document(result, client.offset_encoding, { focus = true })
    end, ctx.bufnr)
end

--- `dart/reanalyze` — ask dartls to re-run analysis for the whole project.
---@param _args string[]
---@param ctx table  { provider, root, bufnr }
---@return nil
local function reanalyze(_args, ctx)
    local client = dart_client(ctx.bufnr)
    if not client then
        return no_client()
    end
    -- custom dartls method — not in the built-in LSP method union
    ---@diagnostic disable-next-line: param-type-mismatch
    client:request("dart/reanalyze", nil, function() end, ctx.bufnr)
    vim.notify("lvim-lang: reanalyzing project", vim.log.levels.INFO, TITLE)
end

--- `lsp restart` — restart dartls (stop then re-enable, which re-attaches).
---@param args string[]
---@param _ctx table
---@return nil
local function lsp(args, _ctx)
    if args[1] ~= "restart" then
        vim.notify("lvim-lang: usage — :LvimLang lsp restart", vim.log.levels.INFO, TITLE)
        return
    end
    local ok, lvim_lsp = pcall(require, "lvim-lsp")
    if not ok then
        vim.notify("lvim-lang: lvim-lsp not available", vim.log.levels.WARN, TITLE)
        return
    end
    lvim_lsp.disable_lsp_server_globally("dart")
    lvim_lsp.enable_lsp_server_globally("dart")
    vim.notify("lvim-lang: dartls restarted", vim.log.levels.INFO, TITLE)
end

--- `fvm` — switch the project's FVM-pinned Flutter SDK version, then invalidate the toolchain.
---@param _args string[]
---@param ctx table  { provider, root, bufnr }
---@return nil
local function fvm(_args, ctx)
    local out = vim.fn.systemlist({ "fvm", "list" })
    if vim.v.shell_error ~= 0 then
        vim.notify("lvim-lang: `fvm list` failed (is FVM installed?)", vim.log.levels.WARN, TITLE)
        return
    end
    local dart_cfg = require("lvim-lang.config").providers.dart or {}
    local fvm_icon = (dart_cfg.icons and dart_cfg.icons.fvm) or "󰐊"
    local items = {}
    for _, line in ipairs(out) do
        local ver = line:match("(%d+%.%d+%.%d+[%w%.%-]*)")
        if ver then
            items[#items + 1] = { label = ver, icon = fvm_icon }
        end
    end
    if #items == 0 then
        vim.notify("lvim-lang: no FVM Flutter versions installed", vim.log.levels.INFO, TITLE)
        return
    end
    ui.pick({ title = "FVM Flutter version", items = items }, function(item)
        if not item then
            return
        end
        vim.fn.system({ "fvm", "use", item.label })
        toolchain.invalidate("dart", ctx.root)
        vim.notify("lvim-lang: FVM → " .. item.label .. " (run :LvimLang lsp restart)", vim.log.levels.INFO, TITLE)
    end)
end

--- `labels` — toggle the closing-labels decorations on/off (live).
---@param _args string[]
---@param _ctx table
---@return nil
local function labels(_args, _ctx)
    local on = decorations.toggle("closing_labels")
    vim.notify("lvim-lang: closing labels " .. (on and "on" or "off"), vim.log.levels.INFO, TITLE)
end

---@type table<string, LvimLangCommand>
local M = {
    run = { impl = run.run, desc = "flutter run --machine on the selected device" },
    attach = { impl = run.attach, desc = "flutter attach --machine" },
    emulators = { impl = devices.pick_emulator, desc = "list and launch an emulator" },
    config = { impl = runcfg.command, desc = "pick the active run configuration (.lvim/lang/run.lua)" },
    devtools = { impl = devtools.open, desc = "start Dart DevTools and open its URL" },
    inspect = { impl = vmservice.inspect_widget, desc = "toggle the widget inspector" },
    paint = { impl = vmservice.visual_debug, desc = "toggle debug paint (visual layout)" },
    brightness = { impl = vmservice.toggle_brightness, desc = "flip app brightness (light/dark)" },
    platform = { impl = vmservice.target_platform, desc = "override the target platform" },
    reload = { impl = run.reload, desc = "hot reload the running app" },
    restart = { impl = run.restart, desc = "hot restart the running app" },
    quit = { impl = run.quit, desc = "stop the running app" },
    detach = { impl = run.detach, desc = "detach from the app (leave it running)" },
    log = {
        impl = run.log,
        desc = "log [toggle|clear] [bottom|top|area|float|right|left] — the dev-log panel",
        complete = function(arg)
            return vim.tbl_filter(function(c)
                return arg == "" or c:find(arg, 1, true) == 1
            end, { "toggle", "clear", "bottom", "top", "area", "float", "right", "left" })
        end,
    },
    super = { impl = super, desc = "jump to the super definition (dart/textDocument/super)" },
    reanalyze = { impl = reanalyze, desc = "re-run dartls analysis (dart/reanalyze)" },
    lsp = { impl = lsp, desc = "lsp restart — restart dartls" },
    labels = { impl = labels, desc = "toggle closing-labels decorations" },
    pub = {
        impl = pub.command,
        desc = "pub get|upgrade|add|remove|outdated — flutter pub through lvim-tasks",
        complete = function(arg)
            return vim.tbl_filter(function(c)
                return arg == "" or c:find(arg, 1, true) == 1
            end, pub.subs())
        end,
    },
    clean = { impl = tasks.clean, desc = "flutter clean" },
    test = { impl = tasks.test, desc = "flutter test" },
    doctor = { impl = tasks.doctor, desc = "flutter doctor -v" },
    build = {
        impl = tasks.build,
        desc = "build <apk|appbundle|linux|web|…> — flutter build",
        complete = function(arg)
            return vim.tbl_filter(function(c)
                return arg == "" or c:find(arg, 1, true) == 1
            end, tasks.build_targets)
        end,
    },
    fvm = { impl = fvm, desc = "switch the FVM-pinned Flutter SDK version" },
    install = { impl = sdk.install, desc = "install the Flutter SDK via lvim-pkg" },
}

return M
