-- lvim-lang.providers.registry.proto: the Protocol Buffers provider (declarative Tier 3 data). protols is the LSP; buf formats and lints.
--
---@module "lvim-lang.providers.registry.proto"

local ROOTS = { "buf.yaml", "buf.work.yaml", ".git" }

--- The include paths protols needs for the project of the current buffer, as `init_options`.
---
--- protols resolves an `import` against its include paths only, and knows neither buf's layout nor where the
--- well-known types live — so `import "question.proto";` (a buf MODULE root, the way protoc / buf see it) and
--- `import "google/protobuf/timestamp.proto";` were both reported as missing. So:
---   • every buf module directory: `modules[].path` of a v2 `buf.yaml`, `directories` of a `buf.work.yaml`,
---     or the root itself (a v1 `buf.yaml` / no buf at all);
---   • the directory holding google/protobuf/*.proto: beside `protoc` (`<prefix>/include`), else the system
---     include dirs.
---@return table?
local function protols_init_options()
    local root = vim.fs.root(0, ROOTS) or vim.uv.cwd()
    if not root then
        return nil
    end
    local paths, seen = {}, {}
    local function add(dir)
        dir = vim.fs.normalize(dir)
        if not seen[dir] and vim.fn.isdirectory(dir) == 1 then
            seen[dir] = true
            paths[#paths + 1] = dir
        end
    end
    --- The `- path: x` / `- x` entries of a top-level YAML list `key` in `file` (enough for buf's files).
    local function list_of(file, key, item)
        local ok, lines = pcall(vim.fn.readfile, root .. "/" .. file)
        if not ok then
            return {}
        end
        local out, inside = {}, false
        for _, l in ipairs(lines) do
            if l:match("^" .. key .. ":") then
                inside = true
            elseif inside and l:match("^%S") then
                inside = false
            elseif inside then
                local v = l:match(item)
                if v then
                    out[#out + 1] = (v:gsub("^[\"']", ""):gsub("[\"']$", ""))
                end
            end
        end
        return out
    end
    local modules = list_of("buf.yaml", "modules", "^%s*%-%s*path:%s*(%S+)")
    for _, d in ipairs(list_of("buf.work.yaml", "directories", "^%s*%-%s*(%S+)")) do
        modules[#modules + 1] = d
    end
    for _, d in ipairs(modules) do
        add(root .. "/" .. d)
    end
    add(root)
    -- the well-known types (google/protobuf/*.proto)
    local protoc = vim.fn.exepath("protoc")
    local candidates = protoc ~= "" and { vim.fs.dirname(vim.fs.dirname(protoc)) .. "/include" } or {}
    vim.list_extend(candidates, { "/usr/include", "/usr/local/include", "/opt/homebrew/include" })
    for _, dir in ipairs(candidates) do
        if vim.uv.fs_stat(dir .. "/google/protobuf/timestamp.proto") then
            add(dir)
            break
        end
    end
    return { include_paths = paths }
end

---@type LvimLangSpecData
return {
    name = "proto",
    filetypes = { "proto" },
    root_patterns = ROOTS,
    lsp = {
        servers = {
            protols = {
                mason = "protols",
                cmd = { "protols" },
                filetypes = { "proto" },
                -- buf's module roots + the well-known types, resolved per project at start
                init_options = protols_init_options,
            },
        },
        default = "protols",
    },
    ft = {
        ["proto"] = {
            formatters = { ["buf"] = { mason = "buf", efm = { formatCommand = "buf format -", formatStdin = true } } },
            linters = {
                ["buf"] = {
                    mason = "buf",
                    efm = {
                        lintCommand = "buf lint ${INPUT}",
                        lintStdin = false,
                        lintIgnoreExitCode = true,
                        lintFormats = { "%f:%l:%c:%m" },
                        rootMarkers = { "buf.yaml", "buf.yml" },
                    },
                },
            },
            defaults = { formatter = false, linter = false },
        },
    },
    commands = {
        build = { cmd = { "buf", "build" }, tool = "buf", group = "Build", desc = "buf build" },
        generate = { cmd = { "buf", "generate" }, tool = "buf", group = "Build", desc = "buf generate" },
        lint = { cmd = { "buf", "lint" }, tool = "buf", group = "Lint", desc = "buf lint" },
    },
    icons = { statusline = "󰅩" },
}
