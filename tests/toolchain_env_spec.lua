-- What a spawned toolchain process is given, and why it is not nothing.
--
-- A tool resolved to an absolute path inside a version-manager install (rustup's
-- rust-analyzer, a mise-pinned go, an FVM SDK) is NOT what the inherited PATH points at. Run
-- directly, its OWN child lookups — rust-analyzer → rustc, gopls → go, jdtls → JAVA_HOME —
-- go through PATH and land in a DIFFERENT install. core.toolchain.env() is what closes that
-- gap, and it has two independent jobs: the bin dir first on PATH, and the `home` var
-- (GOROOT / JAVA_HOME) re-pointed at the same install.
--
-- The first version asked "is this directory on PATH" — presence, not precedence. A pinned
-- install that is on PATH but SHADOWED by an earlier directory of the same name therefore got
-- nothing, which is the whole bug, intact. And the home var was only ever re-pointed as a
-- side effect of changing PATH, so a right PATH with a stale GOROOT stayed stale. Both are
-- the regressions below.

local toolchain = require("lvim-lang.core.toolchain")
local registry = require("lvim-lang.registry")
local state = require("lvim-lang.state")

local tmp = vim.fn.tempname()

--- An executable file at `path` (the directories are created).
---@param path string
---@return string path
local function exe(path)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local f = assert(io.open(path, "w"))
    f:write("#!/bin/sh\nexit 0\n")
    f:close()
    assert(vim.uv.fs_chmod(path, 493)) -- 0755
    return path
end

local PINNED = exe(tmp .. "/pinned/go-1.26.9/bin/go") -- what the toolchain resolves
local OTHER = exe(tmp .. "/other/go-1.26.6/bin/go") -- a second go, reachable through PATH
local SERVER = exe(tmp .. "/pkgs/bin/gopls") -- a server installed apart from the SDK
local NODE = exe(tmp .. "/pinned/node-22/bin/node") -- an OPTIONAL runtime
local EMPTY = tmp .. "/empty" -- a PATH entry holding nothing
local ROOT = tmp .. "/proj"
for _, dir in ipairs({ EMPTY, ROOT }) do
    vim.fn.mkdir(dir, "p")
end

local D_PINNED = vim.fs.normalize(vim.fs.dirname(PINNED))
local D_OTHER = vim.fs.normalize(vim.fs.dirname(OTHER))
local D_SERVER = vim.fs.normalize(vim.fs.dirname(SERVER))
local D_NODE = vim.fs.normalize(vim.fs.dirname(NODE))
local HOME_PINNED = vim.fs.normalize(tmp .. "/pinned/go-1.26.9")
local HOME_OTHER = vim.fs.normalize(tmp .. "/other/go-1.26.6")

-- A provider of our own, so the test says what it means instead of depending on whichever SDKs
-- the machine happens to have. `go` is the primary runtime (resolved eagerly by env), `node` an
-- optional one (used only once something else has cached it), `sh` a "which" winner — a binary
-- found ON PATH, which therefore never needs putting there.
registry.register({
    name = "testlang",
    filetypes = {},
    root_patterns = { ".git" },
    toolchain = {
        tools = {
            go = { { kind = "path", value = PINNED } },
            gopls = { { kind = "path", value = SERVER } },
            node = { { kind = "path", value = NODE } },
            sh = { { kind = "which", value = "sh" } },
        },
        runtimes = {
            { key = "go", require = true, home = "TESTLANG_HOME" },
            { key = "node" },
            { key = "sh", require = true },
        },
    },
})

--- Run `fn` with a PATH built from `entries` and `TESTLANG_HOME` set to `home` (nil unsets it),
--- against a cold toolchain cache. The real environment is restored either way.
---@param entries string[]
---@param home string|nil
---@param fn fun()
local function with(entries, home, fn)
    local saved_path, saved_home = vim.env.PATH, vim.env.TESTLANG_HOME
    toolchain.invalidate("testlang", ROOT)
    state.toolchains[ROOT] = nil
    vim.env.PATH = table.concat(entries, ":")
    vim.env.TESTLANG_HOME = home
    local ok, err = pcall(fn)
    vim.env.PATH, vim.env.TESTLANG_HOME = saved_path, saved_home
    if not ok then
        error(err, 0)
    end
end

---@param path_value string
---@return string[]
local function entries(path_value)
    return vim.split(path_value, ":", { plain = true })
end

--- Which PATH entry a child's lookup of `bin` would actually land in.
---@param path_value string
---@param bin string
---@return string|nil
local function resolves_in(path_value, bin)
    for _, e in ipairs(entries(path_value)) do
        if e ~= "" and vim.fn.executable(vim.fs.normalize(e) .. "/" .. bin) == 1 then
            return vim.fs.normalize(e)
        end
    end
    return nil
end

describe("core.toolchain.env")

it("puts the resolved bin dir first when PATH holds no such binary", function()
    with({ EMPTY }, nil, function()
        local env = toolchain.env("testlang", ROOT, "go")
        truthy(env, "an env is needed")
        eq(D_PINNED, entries(env.PATH)[1], "the resolved install leads")
        eq(EMPTY, entries(env.PATH)[2], "the inherited PATH follows")
    end)
end)

it("puts it first when PATH resolves that name to ANOTHER install", function()
    -- The regression: D_PINNED IS on PATH, but behind a second go. Presence is not precedence.
    with({ D_OTHER, D_PINNED }, nil, function()
        local env = toolchain.env("testlang", ROOT, "go")
        truthy(env, "a shadowed install still needs the env fixed")
        eq(D_PINNED, entries(env.PATH)[1])
        eq(D_PINNED, resolves_in(env.PATH, "go"), "the child now finds the go the editor resolved")
    end)
end)

it("changes nothing when PATH already resolves that name to that install", function()
    with({ D_PINNED, D_OTHER }, HOME_PINNED, function()
        eq(nil, toolchain.env("testlang", ROOT, "go"), "nothing to fix, nothing returned")
    end)
end)

it("re-points the home var even when PATH needs no change", function()
    -- The second regression: a right PATH with a stale GOROOT still runs against another stdlib.
    with({ D_PINNED }, HOME_OTHER, function()
        local env = toolchain.env("testlang", ROOT, "go")
        truthy(env, "a stale home var is reason enough")
        eq(nil, env.PATH, "PATH was already right and is left alone")
        eq(HOME_PINNED, env.TESTLANG_HOME)
    end)
end)

it("leaves a home var that names the same install by another name", function()
    -- `latest` is a version manager's link to the versioned directory beside it.
    local link = tmp .. "/pinned/latest"
    assert(vim.uv.fs_symlink(HOME_PINNED, link) or vim.uv.fs_stat(link))
    with({ D_PINNED }, link, function()
        eq(nil, toolchain.env("testlang", ROOT, "go"), "one install, two spellings, nothing to do")
    end)
end)

it("leaves a home var the editor does not set alone", function()
    with({ D_OTHER }, nil, function()
        local env = toolchain.env("testlang", ROOT, "go")
        eq(D_PINNED, entries(env.PATH)[1])
        eq(nil, env.TESTLANG_HOME, "we re-point a home var; we do not invent one")
    end)
end)

it("never puts a which-resolved runtime on PATH", function()
    -- `sh` is a declared runtime, but it was found BY looking along PATH: it is already where a
    -- child would look, and its directory is the system's, not an install of ours to lead with.
    with({ D_OTHER, "/bin" }, nil, function()
        local sh = toolchain.resolve("testlang", "sh", ROOT)
        truthy(sh and sh ~= "", "the fixture needs an sh on PATH")
        local env = toolchain.env("testlang", ROOT, "go")
        eq(D_PINNED .. ":" .. D_OTHER .. ":/bin", env.PATH, "only the pinned install was added")
    end)
end)

it("keeps a package-managed server's shared bin dir OFF PATH", function()
    -- gopls lives in a bin dir of unrelated tools (prettier, dlv, golangci-lint in the real one).
    -- It holds no runtime for the server to find, and leading PATH with it would shadow the
    -- project's own tools for everything the server shells out to. What gopls must find is go.
    with({ D_OTHER }, nil, function()
        local env = toolchain.env("testlang", ROOT, "gopls")
        eq(D_PINNED, entries(env.PATH)[1], "the SDK it must find")
        for _, e in ipairs(entries(env.PATH)) do
            truthy(e ~= D_SERVER, "the package bin dir must not be prepended")
        end
    end)
end)

it("leads PATH with the runtime that is about to run", function()
    -- `node` is declared second and optional; spawning it makes it the one that leads — and the
    -- one worth resolving, cache or no cache.
    with({ D_OTHER }, nil, function()
        local env = toolchain.env("testlang", ROOT, "node")
        eq(D_NODE, entries(env.PATH)[1], "what is about to run")
        eq(D_PINNED, entries(env.PATH)[2], "then the primary runtime")
    end)
end)

it("names one directory once", function()
    with({ D_OTHER }, nil, function()
        local env = toolchain.env("testlang", ROOT, "go") -- tool and primary runtime are the same
        local count = 0
        for _, e in ipairs(entries(env.PATH)) do
            count = count + (e == D_PINNED and 1 or 0)
        end
        eq(1, count)
    end)
end)

it("lets the caller's own env win", function()
    with({ D_OTHER }, HOME_OTHER, function()
        local env = toolchain.env("testlang", ROOT, "go", { PATH = "/caller", TESTLANG_HOME = "/caller" })
        eq("/caller", env.PATH)
        eq("/caller", env.TESTLANG_HOME)
    end)
end)

it("uses an optional runtime only once something has resolved it", function()
    with({ D_OTHER }, nil, function()
        local before = toolchain.env("testlang", ROOT, "go")
        eq(nil, resolves_in(before.PATH, "node"), "an unresolved optional runtime costs no resolution")
        toolchain.resolve("testlang", "node", ROOT)
        eq(D_NODE, resolves_in(toolchain.env("testlang", ROOT, "go").PATH, "node"), "cached, it is used")
        toolchain.invalidate("testlang", ROOT)
        eq(
            nil,
            resolves_in(toolchain.env("testlang", ROOT, "go").PATH, "node"),
            "invalidated, it is forgotten — path and winning strategy together"
        )
    end)
end)

it("says nothing about a provider with no toolchain", function()
    eq(nil, toolchain.env("no-such-provider", ROOT, "go"))
    eq({ PATH = "/caller" }, toolchain.env("no-such-provider", ROOT, "go", { PATH = "/caller" }))
end)

describe("core.declarative: the runtimes env() reads")

do
    -- env() only knows a provider's runtimes because the declarative factory records them, in
    -- declared order, with the `home` var each one owns. If that ever stops, every env() quietly
    -- loses half its job and nothing else notices.
    local ok = pcall(require, "lvim-lang.providers.go")
    if not ok then
        skip("the go provider declares go as a GOROOT-owning runtime", "needs the sibling lvim-* checkouts")
    else
        it("the go provider declares go as a GOROOT-owning runtime", function()
            local rts = (registry.get("go") or {}).toolchain.runtimes
            truthy(rts and #rts > 0, "the factory recorded no runtimes")
            eq({ key = "go", require = true, home = "GOROOT" }, rts[1])
        end)
        it("java-hosted providers declare JAVA_HOME", function()
            for _, name in ipairs({ "java", "kotlin", "scala", "clojure" }) do
                pcall(require, "lvim-lang.providers." .. name)
                local found
                for _, rt in ipairs(((registry.get(name) or {}).toolchain or {}).runtimes or {}) do
                    if rt.key == "java" then
                        found = rt.home
                    end
                end
                eq("JAVA_HOME", found, name .. " must re-point JAVA_HOME")
            end
        end)
    end
end
