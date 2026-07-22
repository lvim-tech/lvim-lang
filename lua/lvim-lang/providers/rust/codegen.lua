-- lvim-lang.providers.rust.codegen: Rust code generation — macro expansion via cargo-expand.
-- `cargo expand` prints the macro-expanded source; this runs it off the UI thread (vim.system) and
-- shows the result in a scratch `rust` buffer you can read / yank / close. cargo-expand is a
-- `cargo install` tool (not a mason package), so a missing one is reported with an install hint.
--
---@module "lvim-lang.providers.rust.codegen"

local toolchain = require("lvim-lang.core.toolchain")

local TITLE = { title = "lvim-lang" }

local M = {}

--- The Cargo crate root for the current buffer (else cwd).
---@param bufnr integer
---@return string
local function root_of(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
        return vim.fs.root(bufnr, { "Cargo.toml", "Cargo.lock", ".git" }) or vim.fs.dirname(name)
    end
    return vim.uv.cwd() or "."
end

--- Show text in a throwaway `rust` scratch buffer (bottom split, read-only, `q` to close).
---@param title string
---@param text string
---@return nil
local function show_scratch(title, text)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text:gsub("\n$", ""), "\n"))
    vim.bo[buf].filetype = "rust"
    vim.bo[buf].modifiable = false
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.api.nvim_buf_set_name(buf, title)
    vim.cmd("botright split")
    vim.api.nvim_win_set_buf(0, buf)
    vim.wo.winfixheight = true
    vim.api.nvim_win_set_height(0, math.min(20, math.max(6, vim.api.nvim_buf_line_count(buf))))
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true, silent = true })
end

--- `:LvimLang expand [item]` — `cargo expand [item]`, showing the macro-expanded source in a scratch
--- buffer. `item` is an optional module/item path (e.g. `tests::test_add`).
---@param args string[]
---@param ctx table
---@return nil
function M.expand(args, ctx)
    if vim.fn.executable("cargo-expand") ~= 1 then
        vim.notify(
            "lvim-lang: cargo-expand not found — install it with `cargo install cargo-expand`",
            vim.log.levels.WARN,
            TITLE
        )
        return
    end
    local root = ctx.root or root_of(ctx.bufnr)
    local cargo = toolchain.resolve("rust", "cargo", root) or "cargo"
    local cmd = { cargo, "expand" }
    vim.list_extend(cmd, args)
    vim.notify("lvim-lang: expanding macros…", vim.log.levels.INFO, TITLE)
    vim.system(cmd, { cwd = root, text = true }, function(res)
        vim.schedule(function()
            if res.code ~= 0 or not res.stdout or res.stdout == "" then
                vim.notify(
                    "lvim-lang: cargo expand failed: " .. (res.stderr or "no output"),
                    vim.log.levels.ERROR,
                    TITLE
                )
                return
            end
            show_scratch("cargo expand " .. table.concat(args, " "), res.stdout)
        end)
    end)
end

return M
