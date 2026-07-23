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
                ["sql-formatter"] = { mason = "sql-formatter" },
                ["sqlfluff"] = { mason = "sqlfluff" },
                ["pg_format"] = { mason = "pg_format" },
            },
            linters = { ["sqlfluff"] = { mason = "sqlfluff" } },
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
