-- lvim-lang test runner. No framework: a dependency for a handful of files of
-- asserts is a worse trade than twenty lines of harness.
--
--     nvim --headless -u NONE -l tests/run.lua
--
-- or, from the plugin root, `make test`. lvim-lang lives inside the lvim-*
-- ecosystem, so the sibling checkouts next to this one are put on the
-- runtimepath when they exist; a spec that needs one it cannot find SKIPS
-- rather than fails, and says which.

-- A spec may open a store, write a cache or persist state. None of that may reach the real
-- editor's data, so `make test` redirects the XDG homes into a throwaway directory and this is
-- the guard that the redirection actually happened: refuse to run rather than write into
-- ~/.local/share/nvim. (This suite once wrote into the real store twice; a guard is cheaper than
-- remembering.)
local sandbox = vim.env.LVIM_TEST_HOME
local data_dir = vim.fn.stdpath("data")
if not sandbox or sandbox == "" or not vim.startswith(vim.fs.normalize(data_dir), vim.fs.normalize(sandbox)) then
    io.write(
        "refusing to run: the data directory is not a sandbox\n",
        "  stdpath('data') = ",
        data_dir,
        "\n  LVIM_TEST_HOME  = ",
        tostring(sandbox),
        "\nRun the suite through `make test`, which redirects the XDG homes.\n"
    )
    os.exit(2)
end

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
package.path = table.concat({
    root .. "/lua/?.lua",
    root .. "/lua/?/init.lua",
    package.path,
}, ";")

-- The siblings (lvim-utils, lvim-ui, lvim-lsp, lvim-tasks, lvim-pkg, …) as they sit beside this
-- checkout, unless $LVIM_PLUGINS_DIR names another directory holding them.
local plugins = vim.env.LVIM_PLUGINS_DIR
if not plugins or plugins == "" then
    plugins = vim.fs.dirname(root)
end
if vim.uv.fs_stat(plugins) then
    for name, kind in vim.fs.dir(plugins) do
        local dir = plugins .. "/" .. name
        if kind == "directory" and name:match("^lvim%-") and dir ~= root then
            vim.opt.runtimepath:append(dir)
            package.path = table.concat({
                dir .. "/lua/?.lua",
                dir .. "/lua/?/init.lua",
                package.path,
            }, ";")
        end
    end
end

local passed, failed, skipped = 0, 0, 0
local current = "?"

--- Name the group the next tests belong to.
---@param name string
function _G.describe(name)
    current = name
    io.write("\n", name, "\n")
end

--- Run one test; a failure is reported and the run continues.
---@param name string
---@param fn fun()
function _G.it(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        io.write("  ok   ", name, "\n")
    else
        failed = failed + 1
        io.write("  FAIL ", current, " / ", name, "\n       ", (tostring(err):gsub("\n", "\n       ")), "\n")
    end
end

--- Say that a test could not be run here, and why. Counted apart from a pass:
--- "the sibling checkout is missing" must never read as "the code works".
---@param name string
---@param why string
function _G.skip(name, why)
    skipped = skipped + 1
    io.write("  skip ", name, " — ", why, "\n")
end

--- Assert deep equality, showing both sides when they differ.
---@param expected any
---@param got any
---@param what? string
function _G.eq(expected, got, what)
    if not vim.deep_equal(expected, got) then
        error(
            ("%sexpected %s\n     got %s"):format(
                what and (what .. ": ") or "",
                vim.inspect(expected),
                vim.inspect(got)
            ),
            2
        )
    end
end

--- Assert truthiness.
---@param value any
---@param what? string
function _G.truthy(value, what)
    if not value then
        error((what or "expected a truthy value") .. (", got " .. vim.inspect(value)), 2)
    end
end

for _, spec in ipairs({
    "baseline_spec.lua",
    "toolchain_env_spec.lua",
}) do
    dofile(root .. "/tests/" .. spec)
end

io.write(("\n%d passed, %d failed, %d skipped\n"):format(passed, failed, skipped))
os.exit(failed > 0 and 1 or 0)
