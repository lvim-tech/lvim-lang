-- lvim-lang.providers.registry.nextflow: the Nextflow provider (declarative Tier 3). nextflow-language-server is the LSP. `nextflow run` executes a pipeline.
--
---@module "lvim-lang.providers.registry.nextflow"

---@type LvimLangSpecData
return {
    name = "nextflow",
    filetypes = { "nextflow" },
    root_patterns = { "nextflow.config", ".git" },
    lsp = {
        servers = { ["nextflow-language-server"] = { mason = "nextflow-language-server", filetypes = { "nextflow" } } },
        default = "nextflow-language-server",
    },
    ft = {
        ["nextflow"] = { defaults = {} },
    },
    commands = {
        run = {
            cmd = { "nextflow", "run", "${file}" },
            tool = "nextflow",
            group = "Run",
            desc = "nextflow run ${file}",
        },
    },
    icons = { statusline = "󰘚" },
}
