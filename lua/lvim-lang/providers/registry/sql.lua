-- lvim-lang.providers.registry.sql: the SQL provider (declarative Tier 3 data). sqls is the LSP; sql-formatter / sqlfluff / pg_format format; sqlfluff lints.
--
---@module "lvim-lang.providers.registry.sql"

---@type LvimLangSpecData
return {
    name = "sql",
    filetypes = { "sql", "mysql", "plsql" },
    root_patterns = { ".git" },
    lsp = {
        servers = { sqls = { mason = "sqls", cmd = { "sqls" }, filetypes = { "sql", "mysql", "plsql" } } },
        default = "sqls",
    },
    ft = {
        ["sql"] = {
            formatters = {
                ["sql-formatter"] = {
                    mason = "sql-formatter",
                    efm = { formatCommand = "sql-formatter", formatStdin = true },
                },
                -- --dialect=ansi makes sqlfluff work with no project config, but the CLI flag
                -- OVERRIDES a .sqlfluff dialect. On a postgres/mysql project, override the entry:
                -- setup({ providers = { sql = { ft = { sql = { formatters = { sqlfluff = { efm = … } } } } } } }).
                ["sqlfluff"] = {
                    mason = "sqlfluff",
                    efm = { formatCommand = "sqlfluff format --dialect=ansi -", formatStdin = true },
                },
                ["pg_format"] = { mason = "pg_format", efm = { formatCommand = "pg_format -", formatStdin = true } },
            },
            linters = {
                ["sqlfluff"] = {
                    mason = "sqlfluff",
                    efm = {
                        lintCommand = "sqlfluff lint --dialect=ansi --nocolor --disable-progress-bar -",
                        lintStdin = true,
                        lintIgnoreExitCode = true,
                        lintFormats = { "L:%*[ ]%l | P:%*[ ]%c | %*[^|] | %m" },
                    },
                },
            },
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        lint = {
            cmd = { "sqlfluff", "lint", "${file}" },
            tool = "sqlfluff",
            group = "Lint",
            desc = "sqlfluff lint <file>",
        },
    },
    icons = { statusline = "" },
}
