-- lvim-lang.providers.ruby: the Ruby provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Reuses the shared core: the
-- per-filetype catalog (core.catalog), the multi-LSP fan-out (core.lsp.register_catalog), the
-- lvim-tasks runner (core.runner) and on-demand tooling (core.ensure).
--
-- ruby-lsp (Shopify's language server) is the default; solargraph is offered as the alternative. Both
-- are gems (also mason packages) resolved per project — a project's bundled copy wins over the shared
-- mason one. ruby-lsp integrates rubocop for formatting + diagnostics NATIVELY when rubocop is in the
-- bundle, so the per-filetype efm formatter / linter default to `false` (the LSP owns them); the
-- catalog still OFFERS rubocop (and standardrb) through efm for users who prefer efm-based tooling —
-- and `catalog.lsp_on_attach` hands formatting to efm whenever such a formatter IS selected, so the
-- two never both format the buffer. Debugging is rdbg (the `debug` gem — `bundle add debug`, NOT a
-- mason package), wired as a `server` adapter in providers.ruby.dap. build has no meaning for Ruby;
-- run executes the current file, rake runs tasks, and RSpec drives the test commands.
--
---@module "lvim-lang.providers.ruby"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.providers.ruby.toolchain")
local core_toolchain = require("lvim-lang.core.toolchain")
local requirements = require("lvim-lang.core.requirements")

---@type table
local DEFAULTS = {
    -- Explicit binary paths; when set each wins over every other resolution strategy.
    ruby_path = nil,
    bundle_path = nil,
    rubocop_path = nil,
    ruby_lsp_path = nil,
    rdbg_path = nil,
    -- A shell command whose first output line is the `ruby` binary path (checked after ruby_path,
    -- before the version manager / PATH). Empty by default.
    ruby_lookup_cmd = nil,
    -- Version manager for the interpreter: "mise" | "asdf" | "rbenv" | "chruby" | "rvm" | false
    -- (ignore) | function(root). Honours the project's pin (.ruby-version / .tool-versions).
    -- Default: try mise, asdf, rbenv (each `<mgr> which ruby`), then chruby / rvm (~/.rubies).
    version_manager = nil,

    -- The rspec command for `:LvimLang debug-test` when NOT auto-detected (normally "bundle exec
    -- rspec" in a bundled project, else "rspec"); set to force one.
    debug_rspec_command = nil,

    -- LSP server catalog. ruby-lsp is the default; solargraph is offered as the alternative — set
    -- `lsp.server = "solargraph"` (or a list) to switch / add. `role` coordinates overlaps.
    lsp = {
        servers = {
            ["ruby-lsp"] = {
                mason = "ruby-lsp",
                bin = "ruby-lsp",
                filetypes = { "ruby", "eruby" },
                role = "types", -- completion / hover / definition / rename / format / diagnostics
                -- ruby-lsp reads its options from init_options (formatter / linters / enabled
                -- features); the server module injects the resolved values per root.
                init_options = {
                    formatter = "auto", -- "auto" picks rubocop/syntax_tree from the bundle; "none" to disable
                    linters = {}, -- e.g. { "rubocop" } — empty = auto-detect from the bundle
                    enabledFeatures = {
                        codeActions = true,
                        codeLens = true,
                        completion = true,
                        definition = true,
                        diagnostics = true,
                        documentHighlights = true,
                        documentLink = true,
                        documentSymbols = true,
                        foldingRanges = true,
                        formatting = true,
                        hover = true,
                        inlayHint = true,
                        onTypeFormatting = true,
                        selectionRanges = true,
                        semanticHighlighting = true,
                        signatureHelp = true,
                        typeHierarchy = true,
                        workspaceSymbol = true,
                    },
                },
            },
            solargraph = {
                mason = "solargraph",
                bin = "solargraph",
                filetypes = { "ruby" },
                role = "types", -- alternative full server (completion / hover / definition / format)
                settings = {
                    solargraph = {
                        diagnostics = true,
                        formatting = true,
                        completion = true,
                        hover = true,
                        useBundler = true, -- run through the project's bundle when present
                    },
                },
            },
        },
        default = "ruby-lsp",
    },

    -- Per-FILETYPE catalog: formatters / linters for `ruby`, each with an efm config, plus which is
    -- the `default` (or false = none). ruby-lsp formats + diagnoses natively (via rubocop in the
    -- bundle), so both default to `false`; the catalog still OFFERS rubocop and standardrb for users
    -- who prefer efm-based tooling (set ft.ruby.formatter = "rubocop", ft.ruby.linter = "rubocop").
    -- No efm-installed debugger: rdbg comes from the `debug` gem (`bundle add debug`), wired in
    -- providers.ruby.dap — so `debuggers` is empty and the DAP adapter rides on the ruby-lsp server.
    ft = {
        ruby = {
            formatters = {
                rubocop = {
                    mason = "rubocop",
                    -- Autocorrect on stdin: corrected source to stdout, diagnostics to stderr.
                    efm = {
                        formatCommand = "rubocop --stdin ${INPUT} --auto-correct-all --stderr --format quiet",
                        formatStdin = true,
                    },
                },
                standardrb = {
                    mason = "standardrb",
                    efm = {
                        formatCommand = "standardrb --stdin ${INPUT} --fix --stderr --format quiet",
                        formatStdin = true,
                    },
                },
            },
            linters = {
                rubocop = {
                    mason = "rubocop",
                    efm = {
                        lintCommand = "rubocop --stdin ${INPUT} --format emacs --force-exclusion",
                        lintStdin = true,
                        lintFormats = { "%f:%l:%c: %t: %m" },
                        rootMarkers = { ".rubocop.yml", ".rubocop.yaml" },
                    },
                },
                standardrb = {
                    mason = "standardrb",
                    efm = {
                        lintCommand = "standardrb --stdin ${INPUT} --format emacs",
                        lintStdin = true,
                        lintFormats = { "%f:%l:%c: %t: %m" },
                    },
                },
            },
            debuggers = {},
            defaults = { formatter = false, linter = false, debugger = false },
        },
    },

    -- Nerd Font icons used in the Ruby provider's statusline / pickers (all configurable).
    icons = {
        statusline = "", -- the Ruby marker in the statusline segment (nf-dev-ruby)
        test = "󰙨", -- test runner / result row
        build = "󰜫", -- rake / build task row
        run = "󰐊", -- run task row
        debug = "󰃤", -- debug session row
        deps = "󰏗", -- gem / bundle dependency row
    },
}

--- Health section for :checkhealth lvim-lang: whether the Ruby toolchain (interpreter + servers +
--- tools) resolves for the current working directory, and at what version.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."

    local ruby, reason = core_toolchain.resolve("ruby", "ruby", root)
    if ruby then
        local ver = core_toolchain.version("ruby", "ruby", root)
        h.ok(("ruby: %s%s"):format(ruby, ver and ("  (" .. ver .. ")") or ""))
    else
        h.warn(
            ("ruby not found — %s"):format(
                reason or "install Ruby (rbenv/rvm/chruby/asdf/mise) or set providers.ruby.ruby_path"
            )
        )
    end

    -- bundle + rake ship with ruby; ruby-lsp / rubocop are gems (or mason) resolved on demand.
    for _, tool in ipairs({ "bundle", "rake" }) do
        local path = core_toolchain.resolve("ruby", tool, root)
        if path then
            h.ok(("%s: %s"):format(tool, path))
        else
            h.info(("%s not found — install it into the active ruby"):format(tool))
        end
    end
    for _, tool in ipairs({ "ruby-lsp", "rubocop" }) do
        local path = core_toolchain.resolve("ruby", tool, root)
        if path then
            h.ok(("%s: %s"):format(tool, path))
        else
            h.info(
                ("%s not found — installed on demand from the mason registry (or `gem install %s`)"):format(
                    tool,
                    tool
                )
            )
        end
    end

    -- rdbg is the `debug` gem's binary — not mason; advisory only.
    if core_toolchain.resolve("ruby", "rdbg", root) then
        h.ok("rdbg: present (the `debug` gem)")
    else
        h.info("rdbg not found — debugging needs the `debug` gem (`bundle add debug`)")
    end
end

--- Statusline segment for a root: the Ruby marker + the active run config (if any).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.ruby and config.providers.ruby.icons) or {}
    local parts = { ic.statusline or "" }
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
    name = "ruby",
    filetypes = { "ruby", "eruby" },
    root_patterns = { "Gemfile", "Rakefile", ".ruby-version", ".git" },
    statusline = statusline,
    toolchain = toolchain,
    commands = require("lvim-lang.providers.ruby.commands"),
    -- lvim-tasks templates (arg-less bundler subcommands) — also runnable via :LvimLang deps.
    tasks = require("lvim-lang.providers.ruby.deps").templates,
    --- Surfaced at activation + in :checkhealth: a Ruby interpreter must be present (ruby-lsp and the
    --- rubocop / rspec / rake gems all run on it). Ruby is the user's OWN runtime — not lvim-pkg-installed.
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
        return {
            requirements.tool_present(
                "ruby",
                "ruby",
                "Ruby runtime",
                "Install Ruby via a version manager (rbenv / rvm / chruby / asdf / mise) and pin it with "
                    .. ".ruby-version, or set providers.ruby.ruby_path; the language server and tools need it.",
                root
            ),
        }
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
