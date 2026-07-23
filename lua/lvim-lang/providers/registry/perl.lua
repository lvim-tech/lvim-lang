-- lvim-lang.providers.registry.perl: the Perl provider, as declarative DATA (Tier 2).
-- perlnavigator is the LSP (mason `perlnavigator`, launched `… --stdio`); it can drive perltidy /
-- perlcritic itself. perltidy (formatter) and perlcritic (linter) are OFFERED over efm as opt-in
-- alternatives — they are CPAN tools (not mason), resolved from PATH. Debugging is perl-debug-adapter
-- (mason). `perl` runs the current file; `prove` runs the test suite.
--
---@module "lvim-lang.providers.registry.perl"

---@type LvimLangSpecData
return {
    name = "perl",
    filetypes = { "perl" },
    root_patterns = { "cpanfile", "Makefile.PL", "dist.ini", ".git" },

    runtime = {
        bin = "perl",
        key = "perl",
        require = true,
        label = "Perl",
        hint = "Install Perl and put `perl` on PATH; the language server and test runs use it. perltidy / "
            .. "perlcritic come from CPAN (cpanm Perl::Tidy Perl::Critic).",
    },

    lsp = {
        servers = {
            perlnavigator = {
                mason = "perlnavigator",
                filetypes = { "perl" },
                cmd = { "perlnavigator", "--stdio" },
            },
        },
        default = "perlnavigator",
    },

    ft = {
        perl = {
            formatters = {
                perltidy = { efm = { formatCommand = "perltidy -st -q", formatStdin = true } },
            },
            linters = {
                perlcritic = {
                    efm = {
                        lintCommand = 'perlcritic --nocolor --verbose "%f:%l:%c: %m (%s)\\n" ${INPUT}',
                        lintStdin = false,
                        lintFormats = { "%f:%l:%c: %m" },
                    },
                },
            },
            debuggers = {
                ["perl-debug-adapter"] = { mason = "perl-debug-adapter" },
            },
            -- perlnavigator can drive perltidy / perlcritic itself, so both default off.
            defaults = { formatter = false, linter = false, debugger = "perl-debug-adapter" },
        },
    },

    -- Debugging via perl-debug-adapter (Perl::LanguageServer's debugger) — launches the current file.
    dap = {
        adapters = {
            perl = { kind = "executable", tool = "perl-debug-adapter" },
        },
        configurations = {
            perl = {
                {
                    adapter = "perl",
                    request = "launch",
                    name = "Launch (perl-debug-adapter)",
                    program = "${file}",
                    cwd = "${workspaceFolder}",
                    stopOnEntry = false,
                    args = {},
                    env = {},
                },
            },
        },
    },

    commands = {
        run = { cmd = { "perl", "${file}" }, tool = "perl", group = "Run", desc = "perl <file>" },
        test = { cmd = { "prove", "-lr", "t" }, group = "Test", desc = "prove -lr t — run the test suite" },
    },

    icons = {
        statusline = "", -- the Perl marker (nf-seti-perl)
    },
}
