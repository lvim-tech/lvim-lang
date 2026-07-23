-- lvim-lang.providers.ruby: the Ruby provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes/root, the ruby-lsp (default) + solargraph (opt-in) LSP catalog, the per-filetype tool
-- catalog (rubocop / standardrb formatters + linters), requirements, health and statusline.
-- `project_dirs = { "bin" }` makes every mason tool prefer a project binstub. This module then EXTENDS
-- the returned spec with Ruby's rich, ecosystem-specific resolution — the part that is NOT common data:
--   * the interpreter through FIVE managers (rbenv / chruby / rvm / mise / asdf), chruby & rvm having no
--     resolver CLI so the project's `.ruby-version` selects a `~/.rubies` / `~/.rvm/rubies` install;
--   * gem tools (ruby-lsp / solargraph / rubocop) additionally from the SELECTED ruby's gem-bin dir, and
--     the ruby-shipped bundle / rake / rspec / rdbg (the `debug` gem — not mason) resolved the same way;
--   * the run / rake / RSpec / rdbg command surface (providers.ruby.commands / .dap / .deps).
--
-- The reusable builders (explicit / lookup / project-local / mason / PATH) come from core.detect via the
-- factory; only the Ruby-specific resolvers live here. ruby-lsp / solargraph keep their bespoke
-- servers/*.lua modules (a real file wins over the generic shim).
--
---@module "lvim-lang.providers.ruby"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")
local detect = require("lvim-lang.core.detect")
local core_toolchain = require("lvim-lang.core.toolchain")

-- Explicit overrides live under `bin_paths`; `ruby_lookup_cmd` holds an optional path-printing lookup.
---@type LvimLangSpecData
local DATA = {
    name = "ruby",
    filetypes = { "ruby", "eruby" },
    root_patterns = { "Gemfile", "Rakefile", ".ruby-version", ".git" },

    -- ruby is the user's own runtime (required); its resolution is overridden in the extend to honour the
    -- Ruby version managers. The generic strategy the factory builds here is replaced below.
    runtime = {
        bin = "ruby",
        key = "ruby",
        lookup_key = "ruby_lookup_cmd",
        require = true,
        label = "Ruby runtime",
        hint = "Install Ruby via a version manager (rbenv / rvm / chruby / asdf / mise) and pin it with "
            .. ".ruby-version, or set providers.ruby.bin_paths.ruby; the language server and tools need it.",
    },

    -- A project that ran `bundle binstubs` (or ships bin/rubocop, bin/rspec) is preferred over a global.
    project_dirs = { "bin" },

    lsp = {
        servers = {
            ["ruby-lsp"] = {
                mason = "ruby-lsp",
                bin = "ruby-lsp",
                filetypes = { "ruby", "eruby" },
                role = "types", -- completion / hover / definition / rename / format / diagnostics
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

    ft = {
        ruby = {
            formatters = {
                rubocop = {
                    mason = "rubocop",
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
                rufo = { mason = "rufo", efm = { formatCommand = "rufo", formatStdin = true } },
                rubyfmt = { mason = "rubyfmt", efm = { formatCommand = "rubyfmt", formatStdin = true } },
                stree = { mason = "stree", efm = { formatCommand = "stree format -", formatStdin = true } },
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
                semgrep = {
                    mason = "semgrep",
                    efm = {
                        lintCommand = "semgrep scan --config auto --quiet --error --disable-version-check --gitlab-sast ${INPUT}",
                        lintStdin = false,
                        lintFormats = { "%f:%l:%c: %m" },
                    },
                },
            },
            debuggers = {},
            -- ruby-lsp formats + diagnoses natively (rubocop in the bundle) → both default false; the
            -- catalog still OFFERS rubocop / standardrb over efm.
            defaults = { formatter = false, linter = false, debugger = false },
        },
    },

    icons = {
        statusline = "", -- the Ruby marker in the statusline segment (nf-dev-ruby)
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗", -- gem / bundle dependency row
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND: Ruby's ecosystem-specific toolchain resolution ──────────────────────────────────────────

--- The ruby config block.
---@return table
local function opts()
    return config.providers.ruby or {}
end

--- The `<name>` from the project's `.ruby-version` (e.g. "3.3.4" / "ruby-3.3.4"), trimmed, or nil.
---@param root string
---@return string|nil
local function pinned_version(root)
    local path = vim.fs.joinpath(root, ".ruby-version")
    if vim.fn.filereadable(path) ~= 1 then
        return nil
    end
    for _, line in ipairs(vim.fn.readfile(path) or {}) do
        local trimmed = vim.trim(line)
        if trimmed ~= "" then
            return trimmed
        end
    end
    return nil
end

--- chruby / rvm have no resolver CLI, so the selected ruby is found on disk: the project's
--- `.ruby-version` name matched against `~/.rubies/<name>/bin/ruby` / `~/.rvm/rubies/<name>/bin/ruby`
--- (bare "3.3.4" or prefixed "ruby-3.3.4").
---@param root string
---@return string|nil
local function via_rubies_dir(root)
    local ver = pinned_version(root)
    if not ver then
        return nil
    end
    local home = vim.env.HOME or vim.uv.os_homedir()
    if not home then
        return nil
    end
    local names = { ver }
    if not ver:match("^ruby%-") then
        names[#names + 1] = "ruby-" .. ver
    end
    for _, r in ipairs({ vim.fs.joinpath(home, ".rubies"), vim.fs.joinpath(home, ".rvm", "rubies") }) do
        for _, name in ipairs(names) do
            local path = vim.fs.joinpath(r, name, "bin", "ruby")
            if vim.fn.executable(path) == 1 then
                return path
            end
        end
    end
    return nil
end

--- Resolve `ruby` through the configured manager, honouring the project pin: mise / asdf / rbenv via
--- `<mgr> which ruby`, chruby / rvm via their rubies dir. `version_manager` may name one, be false, or
--- be a function(root) -> path|nil.
---@param root string
---@return string|nil
local function ruby_vm(root)
    local vm = opts().version_manager
    if vm == false then
        return nil
    end
    if type(vm) == "function" then
        return vm(root)
    end
    local managers = type(vm) == "string" and { vm } or { "mise", "asdf", "rbenv", "chruby", "rvm" }
    for _, mgr in ipairs(managers) do
        if mgr == "chruby" or mgr == "rvm" then
            local path = via_rubies_dir(root)
            if path then
                return path
            end
        elseif vim.fn.executable(mgr) == 1 then
            local out = vim.system({ mgr, "which", "ruby" }, { cwd = root, text = true }):wait()
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

--- A gem tool `bin` inside the SELECTED ruby's bin dir (where `gem install` drops executables):
--- `<dirname(ruby)>/<bin>`. Tracks a version-managed ruby's own gems.
---@param bin string
---@return fun(root: string): string|nil
local function in_ruby_bin(bin)
    return function(root)
        local ruby = core_toolchain.resolve("ruby", "ruby", root)
        if not ruby then
            return nil
        end
        local path = vim.fs.joinpath(vim.fs.dirname(ruby), bin)
        return vim.fn.executable(path) == 1 and path or nil
    end
end

local tc = spec.toolchain.tools
-- Interpreter: explicit → lookup → the five version managers → PATH (replaces the generic strategy).
tc.ruby = {
    { kind = "path", value = detect.explicit("ruby", "ruby") },
    { kind = "path", value = detect.lookup("ruby", "ruby_lookup_cmd") },
    { kind = "path", value = ruby_vm },
    { kind = "which", value = "ruby" },
}
-- Gem-provided servers + rubocop: insert the selected ruby's gem-bin just before the mason fallback
-- (the factory left explicit → binstub → mason → PATH).
for _, key in ipairs({ "ruby-lsp", "solargraph", "rubocop" }) do
    if tc[key] then
        table.insert(tc[key], #tc[key], { kind = "path", value = in_ruby_bin(key) })
    end
end
-- ruby-shipped / gem tools the commands invoke (not in the install union): binstub → gem-bin → PATH.
tc.bundle = {
    { kind = "path", value = detect.explicit("ruby", "bundle") },
    { kind = "path", value = in_ruby_bin("bundle") },
    { kind = "which", value = "bundle" },
}
tc.rake = {
    { kind = "path", value = detect.in_project("bin", "rake") },
    { kind = "path", value = in_ruby_bin("rake") },
    { kind = "which", value = "rake" },
}
tc.rspec = {
    { kind = "path", value = detect.in_project("bin", "rspec") },
    { kind = "path", value = in_ruby_bin("rspec") },
    { kind = "which", value = "rspec" },
}
tc.rdbg = {
    { kind = "path", value = detect.explicit("ruby", "rdbg") },
    { kind = "path", value = detect.in_project("bin", "rdbg") },
    { kind = "path", value = in_ruby_bin("rdbg") },
    { kind = "which", value = "rdbg" },
}

-- The rspec command for :LvimLang debug-test when not auto-detected (else "bundle exec rspec" / "rspec").
defaults.debug_rspec_command = nil

-- The run / rake / RSpec / rdbg command surface + arg-less bundler templates.
spec.commands = require("lvim-lang.providers.ruby.commands")
spec.tasks = require("lvim-lang.providers.ruby.deps").templates

registry.register(spec, defaults)

return spec
