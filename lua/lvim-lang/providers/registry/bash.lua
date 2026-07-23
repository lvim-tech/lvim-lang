-- lvim-lang.providers.registry.bash: the Bash / Shell provider, as declarative DATA (Tier 2).
-- bash-language-server is the LSP (it integrates shellcheck for diagnostics, launched `… start`). The
-- catalog OFFERS every mason shell tool: formatters shfmt (default) / beautysh / shellharden; linters
-- shellcheck / shellharden. Debugging is bash-debug-adapter (bashdb). `bash` runs the current script;
-- `:LvimLang check` runs shellcheck.
--
---@module "lvim-lang.providers.registry.bash"

-- Shared per-filetype catalog for `sh` and `bash`.
---@return table
local function ft_block()
    return {
        formatters = {
            shfmt = {
                mason = "shfmt",
                efm = { formatCommand = "shfmt -i 2 -", formatStdin = true },
            },
            beautysh = {
                mason = "beautysh",
                efm = { formatCommand = "beautysh -", formatStdin = true },
            },
            shellharden = {
                mason = "shellharden",
                efm = { formatCommand = "shellharden --transform ''", formatStdin = true },
            },
        },
        linters = {
            shellcheck = {
                mason = "shellcheck",
                efm = {
                    lintCommand = "shellcheck --format=gcc --external-sources -",
                    lintStdin = true,
                    lintFormats = {
                        "%f:%l:%c: %trror: %m",
                        "%f:%l:%c: %tarning: %m",
                        "%f:%l:%c: %tote: %m",
                    },
                },
            },
            shellharden = {
                mason = "shellharden",
                efm = { lintCommand = "shellharden --check ''", lintStdin = true, lintFormats = { "%m" } },
            },
        },
        debuggers = {
            ["bash-debug-adapter"] = { mason = "bash-debug-adapter" },
        },
        -- bash-language-server already surfaces shellcheck diagnostics; shfmt is the default formatter.
        defaults = { formatter = "shfmt", linter = false, debugger = "bash-debug-adapter" },
    }
end

---@type LvimLangSpecData
return {
    name = "bash",
    filetypes = { "sh", "bash" },
    root_patterns = { ".git" },

    runtime = {
        bin = "bash",
        key = "bash",
        require = false,
        label = "bash",
        hint = "A POSIX shell is needed to run/debug scripts; bash-language-server itself runs on Node.js.",
    },

    lsp = {
        servers = {
            ["bash-language-server"] = {
                mason = "bash-language-server",
                filetypes = { "sh", "bash" },
                cmd = { "bash-language-server", "start" },
            },
        },
        default = "bash-language-server",
    },

    ft = {
        sh = ft_block(),
        bash = ft_block(),
    },

    -- Debugging via bash-debug-adapter (bashdb): launches the current script under the debugger.
    dap = {
        adapters = {
            bashdb = { kind = "executable", tool = "bash-debug-adapter" },
        },
        configurations = {
            sh = {
                {
                    adapter = "bashdb",
                    request = "launch",
                    name = "Launch script (bashdb)",
                    program = "${file}",
                    cwd = "${workspaceFolder}",
                    pathBash = "bash",
                    pathCat = "cat",
                    pathMkfifo = "mkfifo",
                    pathPkill = "pkill",
                    args = {},
                    env = {},
                    terminalKind = "integrated",
                },
            },
        },
    },

    commands = {
        run = { cmd = { "bash", "${file}" }, tool = "bash", group = "Run", desc = "bash <file>" },
        check = {
            cmd = { "shellcheck", "${file}" },
            tool = "shellcheck",
            ensure = { mason = "shellcheck" },
            group = "Test",
            desc = "shellcheck <file>",
        },
    },

    icons = {
        statusline = "", -- terminal glyph (nf-dev-terminal)
    },
}
