-- lvim-lang.providers.registry.cmake: the CMake provider (declarative Tier 3). cmake-language-server is the LSP; gersemi / cmake-format format; cmake-lint lints.
--
---@module "lvim-lang.providers.registry.cmake"

---@type LvimLangSpecData
return {
    name = "cmake",
    filetypes = { "cmake" },
    root_patterns = { "CMakeLists.txt", "CMakePresets.json", ".git" },
    lsp = {
        servers = { ["cmake-language-server"] = { mason = "cmake-language-server", filetypes = { "cmake" } } },
        default = "cmake-language-server",
    },
    ft = {
        ["cmake"] = {
            formatters = {
                ["gersemi"] = { mason = "gersemi" },
                ["cmake-format"] = { mason = "cmakelang", bin = "cmake-format" },
            },
            linters = { ["cmake-lint"] = { mason = "cmakelang", bin = "cmake-lint" } },
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        configure = { cmd = { "cmake", "-B", "build" }, tool = "cmake", group = "Build", desc = "cmake -B build" },
        build = { cmd = { "cmake", "--build", "build" }, tool = "cmake", group = "Build", desc = "cmake --build build" },
    },
    icons = { statusline = "" },
}
