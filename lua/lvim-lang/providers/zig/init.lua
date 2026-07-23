-- lvim-lang.providers.zig: the Zig provider (base + extend).
-- Built through the shared factory (core.declarative): a DATA record supplies the common skeleton —
-- name/filetypes/root, the zls catalog, the per-filetype tool catalog (zig fmt formatter + lldb-dap /
-- codelldb debuggers), the zig toolchain, the requirement, health and statusline. Zig is a compiled
-- systems language served by ONE binary — `zig` is the compiler, build system, test runner AND formatter
-- (`zig fmt` is a subcommand, not a separate tool). This module then EXTENDS the returned spec with Zig's
-- idiosyncratic parts:
--   * the version prober is DATA (`zig version` is a SUBCOMMAND, while zls / lldb-dap use `--version`);
--   * the build output dir (used to default the debugger's executable prompt);
--   * the project-shape-adaptive command surface (build.zig project vs single file — providers.zig.commands
--     / .tasks / .test / .dap / .deps).
--
-- zls formats natively (it shells out to `zig fmt`) so the efm formatter defaults off. zls keeps its
-- bespoke servers/zls.lua (it points zls at the resolved `zig` via zig_exe_path — a real file wins).
--
---@module "lvim-lang.providers.zig"

local registry = require("lvim-lang.registry")
local declarative = require("lvim-lang.core.declarative")

---@type LvimLangSpecData
local DATA = {
    name = "zig",
    filetypes = { "zig", "zir" },
    root_patterns = { "build.zig", "build.zig.zon", ".git" },

    runtime = {
        bin = "zig",
        key = "zig",
        lookup_key = "zig_lookup_cmd",
        require = true,
        label = "Zig toolchain",
        hint = "Install the Zig toolchain (https://ziglang.org/download) and put `zig` on PATH (or manage it "
            .. "with mise / asdf). `zig fmt` ships with it; zls resolves the standard library through it.",
    },
    -- The `zig` binary answers `zig version` (a SUBCOMMAND); zls / lldb-dap use `--version`.
    version = function(bin)
        local base = vim.fs.basename(bin)
        local argv = (base:match("zig") and not base:match("zls")) and { bin, "version" } or { bin, "--version" }
        local out = vim.fn.systemlist(argv)
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

    lsp = {
        servers = {
            zls = {
                mason = "zls",
                filetypes = { "zig" },
                role = "types", -- completion / hover / definition / rename / inlay hints / format
                settings = {
                    zls = {
                        enable_build_on_save = true, -- run `zig build` on save for richer diagnostics
                        semantic_tokens = "full",
                        inlay_hints_show_parameter_name = true,
                        inlay_hints_show_builtin = true,
                        warn_style = true,
                    },
                },
            },
        },
        default = "zls",
    },

    ft = {
        zig = {
            formatters = {
                -- The formatter ships inside the `zig` binary; `zig fmt --stdin` reads stdin and writes
                -- the formatted source to stdout (efm's format contract). Opt-in — zls formats by default.
                ["zig-fmt"] = { efm = { formatCommand = "zig fmt --stdin", formatStdin = true } },
            },
            linters = {},
            debuggers = {
                ["lldb-dap"] = { mason = "lldb-dap" },
                codelldb = { mason = "codelldb" },
            },
            defaults = { formatter = false, linter = false, debugger = "lldb-dap" },
        },
    },

    icons = {
        statusline = "", -- the Zig marker in the statusline segment
        test = "󰙨",
        build = "󰜫",
        run = "󰐊",
        debug = "󰃤",
        deps = "󰏗", -- build.zig.zon dependency row
    },
}

local spec, defaults = declarative.build(DATA)

-- ── EXTEND ─────────────────────────────────────────────────────────────────────────────────────────

-- The Zig build output dir (relative to the project root), where `zig build` drops binaries — used to
-- default the debugger's "path to executable" prompt.
defaults.bin_dir = "zig-out/bin"

spec.commands = require("lvim-lang.providers.zig.commands")
spec.tasks = require("lvim-lang.providers.zig.deps").templates

registry.register(spec, defaults)

return spec
