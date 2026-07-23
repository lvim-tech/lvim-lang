-- lvim-lang.providers.ocaml: the OCaml provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes/root (the whole OCaml family: ocaml / .mli / ocamllex / menhir / dune), the ocaml-lsp
-- catalog, the per-filetype tool catalog (ocamlformat + ocamlearlybird), the ocaml + dune requirements,
-- health and statusline. This module then EXTENDS the returned spec with OCaml's idiosyncratic toolchain:
-- everything is resolved through the active OPAM switch (`opam var bin` in the project root, honouring a
-- local `_opam/`), which the generic mise/asdf resolver cannot express. dune build/exec/test/utop + opam
-- deps + earlybird debugging come from providers.ocaml.commands / .dap / .deps.
--
-- ocaml-lsp keeps its bespoke servers/ocaml-lsp.lua (a real file wins over the generic shim).
--
---@module "lvim-lang.providers.ocaml"

local config = require("lvim-lang.config")
local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")
local detect = require("lvim-lang.core.detect")

-- The ocamlformat efm entry, shared by the `.ml` and `.mli` filetypes. `--name ${INPUT}` tells
-- ocamlformat the source kind from the real filename while it reads stdin; `rootMarkers` gates efm to
-- projects that carry a `.ocamlformat` (ocamlformat requires one).
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

---@type LvimLangSpecData
local DATA = {
    name = "ocaml",
    filetypes = { "ocaml", "ocaml.interface", "ocamllex", "menhir", "dune" },
    root_patterns = { "dune-project", ".git" },

    runtimes = {
        {
            bin = "ocaml",
            key = "ocaml",
            lookup_key = "ocaml_lookup_cmd",
            require = true,
            label = "OCaml toolchain",
            hint = "Install OCaml via opam (`opam switch create <version>`) and put `ocaml` on PATH; "
                .. "ocaml-lsp needs the switch's compiler.",
        },
        {
            bin = "dune",
            key = "dune",
            require = true,
            label = "dune build system",
            hint = "Install dune (`opam install dune`) and put it on PATH — it drives build / exec / test.",
        },
    },

    lsp = {
        servers = {
            ["ocaml-lsp"] = {
                mason = "ocaml-lsp-server", -- mason package name
                bin = "ocamllsp", -- the installed binary differs from the package name
                filetypes = { "ocaml", "ocaml.interface", "ocamllex", "menhir", "dune" },
                role = "types", -- completion / hover / definition / rename / inlay hints / format
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

    icons = {
        statusline = "", -- the OCaml marker in the statusline segment (nf-seti-ocaml)
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗", -- opam dependency row
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND: OPAM-switch toolchain resolution ────────────────────────────────────────────────────────

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

--- A resolver for `tool` through the active opam switch. `version_manager` may be "opam" (default),
--- false to disable, or a function(root, tool) -> path|nil.
---@param tool string
---@return fun(root: string): string|nil
local function via_opam(tool)
    return function(root)
        local vm = (config.providers.ocaml or {}).version_manager
        if vm == false then
            return nil
        end
        if type(vm) == "function" then
            return vm(root, tool)
        end
        local dir = opam_bin_dir(root)
        if not dir then
            return nil
        end
        local path = vim.fs.joinpath(dir, tool)
        return vim.fn.executable(path) == 1 and path or nil
    end
end

local tc = spec.toolchain.tools
-- Compiler / build tool: explicit → lookup → the opam switch → PATH.
tc.ocaml = {
    { kind = "path", value = detect.explicit("ocaml", "ocaml") },
    { kind = "path", value = detect.lookup("ocaml", "ocaml_lookup_cmd") },
    { kind = "path", value = via_opam("ocaml") },
    { kind = "which", value = "ocaml" },
}
tc.dune = {
    { kind = "path", value = detect.explicit("ocaml", "dune") },
    { kind = "path", value = via_opam("dune") },
    { kind = "which", value = "dune" },
}
-- The language server (binary `ocamllsp`): explicit → opam switch → mason → PATH.
tc["ocaml-lsp"] = {
    { kind = "path", value = detect.explicit("ocaml", "ocaml-lsp") },
    { kind = "path", value = via_opam("ocamllsp") },
    { kind = "path", value = detect.in_mason("ocamllsp") },
    { kind = "which", value = "ocamllsp" },
}
-- ocamlformat: explicit → opam switch → mason → PATH.
tc.ocamlformat = {
    { kind = "path", value = detect.explicit("ocaml", "ocamlformat") },
    { kind = "path", value = via_opam("ocamlformat") },
    { kind = "path", value = detect.in_mason("ocamlformat") },
    { kind = "which", value = "ocamlformat" },
}
-- opam itself (for dependency commands + health); only ever on PATH.
tc.opam = { { kind = "which", value = "opam" } }

-- The dune build directory NAME (used to default the debugger's bytecode prompt, `_build/default/…`).
defaults.build_dir = "_build"

spec.commands = require("lvim-lang.providers.ocaml.commands")
spec.tasks = require("lvim-lang.providers.ocaml.deps").templates

registry.register(spec, defaults)

return spec
