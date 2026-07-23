-- lvim-lang.providers.ocaml: the OCaml provider.
-- Assembles the LvimLangProvider spec and self-registers with the core registry on require
-- (lvim-lang.setup loads this module from BUILTIN_PROVIDERS). Reuses the Rust/Go core: the
-- per-filetype catalog (core.catalog), the LSP fan-out (core.lsp.register_catalog), the lvim-tasks
-- runner (core.runner) and on-demand tooling (core.ensure).
--
-- One provider covers the whole OCaml family (ocaml / .mli interfaces / ocamllex / menhir / dune
-- files); a single LSP server — ocaml-lsp (binary `ocamllsp`) — attaches to all of them and formats
-- via ocamlformat natively (exactly as rust-analyzer drives rustfmt), so the default efm formatter /
-- linter are `false` — formatting from the LSP, the catalog still OFFERS ocamlformat via efm (gated
-- on a `.ocamlformat` marker). dune is the single build tool: build / exec / test / utop / fmt go
-- through it (providers.ocaml.tasks); dependencies are declared in dune-project / *.opam and
-- installed via opam (providers.ocaml.deps). Debugging is earlybird (bytecode) through lvim-dap.
--
-- The OCaml toolchain is the user's own — installed and switched through opam (a project-local
-- `_opam/` switch wins); nothing is installed here (ocaml-lsp-server / ocamlformat may also come from
-- the mason registry through the installer).
--
---@module "lvim-lang.providers.ocaml"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local toolchain = require("lvim-lang.core.toolchain")
local requirements = require("lvim-lang.core.requirements")

-- The ocamlformat efm entry, shared by the `.ml` and `.mli` filetypes (ocamlformat formats both).
-- `--name ${INPUT}` tells ocamlformat the source kind from the real filename while it reads stdin;
-- `rootMarkers` gates efm to projects that carry a `.ocamlformat` (ocamlformat requires one).
---@return table
local function ocamlformat_entry()
    return {
        mason = "ocamlformat",
        efm = {
            formatCommand = "ocamlformat --name ${INPUT} -",
            formatStdin = true,
            rootMarkers = { ".ocamlformat" },
        },
    }
end

---@type table
local DEFAULTS = {
    -- Explicit binary paths; each wins over every other resolution strategy.
    ocaml_path = nil,
    dune_path = nil,
    ocaml_lsp_path = nil, -- the `ocamllsp` binary
    ocamlformat_path = nil,
    earlybird_path = nil, -- the `ocamlearlybird` debug adapter
    ocaml_lookup_cmd = nil, -- shell command whose first line is the `ocaml` path
    -- Version manager for the toolchain: "opam" | false | function(root, tool). Honours a
    -- project-local `_opam/` switch. Default: the active opam switch (`opam var bin`) → PATH.
    version_manager = nil,

    -- The dune build directory NAME (relative to the project root). Used to default the debugger's
    -- bytecode prompt (`_build/default/…`).
    build_dir = "_build",

    -- LSP server catalog. ocaml-lsp is the single server; its options live under `init_options`
    -- (ocaml-lsp is configured through initializationOptions, not workspace settings).
    lsp = {
        servers = {
            ["ocaml-lsp"] = {
                mason = "ocaml-lsp-server", -- mason package name
                bin = "ocamllsp", -- the installed binary differs from the package name
                filetypes = { "ocaml", "ocaml.interface", "ocamllex", "menhir", "dune" },
                role = "types", -- completion / hover / definition / rename / inlay hints / format
                -- ocaml-lsp initializationOptions (not workspace settings).
                init_options = {
                    codelens = { enable = true },
                    extendedHover = { enable = true },
                    inlayHints = { hintPatternVariables = false, hintLetBindings = false },
                    duneDiagnostics = { enable = true },
                    syntaxDocumentation = { enable = true },
                },
                settings = {},
            },
        },
        default = "ocaml-lsp",
    },

    -- Per-FILETYPE catalog: formatters / linters / debuggers, each with a default config, plus which
    -- is the `default` (or false = none). ocaml-lsp formats via ocamlformat natively, so the efm
    -- formatter defaults to `false` (the catalog OFFERS ocamlformat via efm on the `.ml` / `.mli`
    -- filetypes for users who prefer efm-based formatting; it is gated on a `.ocamlformat` marker).
    ft = {
        ocaml = {
            formatters = { ocamlformat = ocamlformat_entry() },
            linters = {},
            debuggers = {
                ocamlearlybird = { mason = "ocamlearlybird" },
            },
            defaults = { formatter = false, linter = false, debugger = "ocamlearlybird" },
        },
        ["ocaml.interface"] = {
            formatters = { ocamlformat = ocamlformat_entry() },
            linters = {},
            defaults = { formatter = false, linter = false },
        },
        ocamllex = { defaults = {} },
        menhir = { defaults = {} },
        dune = { defaults = {} },
    },

    -- Statusline / picker icons (Nerd Font, single-width, all configurable).
    icons = {
        statusline = "", -- the OCaml marker in the statusline segment (nf-seti-ocaml)
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗", -- opam dependency row
    },
}

--- Health section for :checkhealth lvim-lang: report whether the OCaml toolchain resolves for the
--- current working directory, and at what version.
---@param h table  the vim.health reporter
---@return nil
local function health(h)
    local root = vim.uv.cwd() or "."
    local report = {
        { tool = "ocaml", level = "warn", hint = "install OCaml via opam (`opam switch create <version>`)" },
        { tool = "dune", level = "warn", hint = "install dune (`opam install dune`)" },
        { tool = "ocaml-lsp", level = "info", hint = "`opam install ocaml-lsp-server` or the mason registry" },
        { tool = "ocamlformat", level = "info", hint = "`opam install ocamlformat` or the mason registry" },
        { tool = "opam", level = "info", hint = "install opam (the OCaml package manager)" },
    }
    for _, r in ipairs(report) do
        local path, reason = toolchain.resolve("ocaml", r.tool, root)
        if path then
            local ver = toolchain.version("ocaml", r.tool, root)
            h.ok(("%s: %s%s"):format(r.tool, path, ver and ("  (" .. ver .. ")") or ""))
        elseif r.level == "warn" then
            h.warn(("%s not found — %s"):format(r.tool, reason or r.hint))
        else
            h.info(("%s not found — %s"):format(r.tool, r.hint))
        end
    end
end

--- Statusline segment for a root: the OCaml marker + the active run config (if any).
---@param root string
---@return string
local function statusline(root)
    local ic = (config.providers.ocaml and config.providers.ocaml.icons) or {}
    local parts = { ic.statusline or "" }
    local rc = require("lvim-lang.core.runcfg").active(root)
    if rc and rc.name then
        parts[#parts + 1] = "➤ " .. rc.name
    end
    return table.concat(parts, "  ")
end

---@type LvimLangProvider
local spec = {
    name = "ocaml",
    filetypes = { "ocaml", "ocaml.interface", "ocamllex", "menhir", "dune" },
    root_patterns = { "dune-project", ".git" },
    statusline = statusline,
    toolchain = require("lvim-lang.providers.ocaml.toolchain"),
    commands = require("lvim-lang.providers.ocaml.commands"),
    -- lvim-tasks templates (arg-less opam dependency subcommands) — also via :LvimLang deps.
    tasks = require("lvim-lang.providers.ocaml.deps").templates,
    --- Surfaced at activation + in :checkhealth: OCaml + dune must be present (ocaml-lsp needs the
    --- switch's compiler; dune drives build / test).
    ---@param root string
    ---@return LvimLangRequirement[]
    requirements = function(root)
        return {
            requirements.tool_present(
                "ocaml",
                "ocaml",
                "OCaml toolchain",
                "Install OCaml via opam (`opam switch create <version>`) and put `ocaml` on PATH; "
                    .. "ocaml-lsp needs the switch's compiler.",
                root
            ),
            requirements.tool_present(
                "ocaml",
                "dune",
                "dune build system",
                "Install dune (`opam install dune`) and put it on PATH — it drives build / exec / test.",
                root
            ),
        }
    end,
    health = health,
}

registry.register(spec, DEFAULTS)

return spec
