# lvim-lang

A unified per-language development-tooling base for the lvim-tech ecosystem.

Instead of a separate plugin per language, `lvim-lang` is one **thin core** — a provider registry,
toolchain resolution, structured daemon sessions, and a notification-driven decoration engine —
into which per-language **providers** plug. The core owns none of the heavy machinery: LSP goes
through `lvim-lsp`/`lvim-ls`, process running through `lvim-tasks`, debugging through `lvim-dap`,
installation through `lvim-pkg`, and every window through `lvim-ui`. A provider is therefore
(almost) pure language semantics, and adding a language is a new `providers/<lang>` module that
self-registers — the core is never touched.

Everything is **lazy**: nothing is wired for a language until the first buffer of its filetype is
opened, at which point that project's root is resolved and the provider is activated once.

## Providers

Each provider owns a language's full tooling — LSP server(s) + settings, a per-filetype catalog of
formatters / linters / debuggers, tasks, dependencies, codegen, debugging and run configs. You pick
the active tools (or none) and override any setting; the chosen tools auto-install through the
unified `lvim-installer` popup when you open a file.

| Provider | Filetypes | LSP | Docs |
| --- | --- | --- | --- |
| Dart / Flutter | `dart` | dartls | [docs/providers/dart.md](docs/providers/dart.md) |
| Go | `go`, `gomod`, `gowork`, `gotmpl` | gopls | [docs/providers/go.md](docs/providers/go.md) |
| Rust | `rust` | rust-analyzer | [docs/providers/rust.md](docs/providers/rust.md) |
| Python | `python` | basedpyright + ruff | [docs/providers/python.md](docs/providers/python.md) |
| TypeScript / JavaScript | `typescript`, `typescriptreact`, `javascript`, `javascriptreact` | vtsls + eslint | [docs/providers/typescript.md](docs/providers/typescript.md) |
| C / C++ | `c`, `cpp`, `objc`, `objcpp` | clangd | [docs/providers/cpp.md](docs/providers/cpp.md) |
| Java | `java` | jdtls | [docs/providers/java.md](docs/providers/java.md) |
| C# / .NET | `cs` | omnisharp (roslyn opt-in) | [docs/providers/csharp.md](docs/providers/csharp.md) |
| F# / .NET | `fsharp` | fsautocomplete | [docs/providers/fsharp.md](docs/providers/fsharp.md) |
| Ruby | `ruby`, `eruby` | ruby-lsp (solargraph opt-in) | [docs/providers/ruby.md](docs/providers/ruby.md) |
| PHP | `php` | intelephense (phpactor opt-in) | [docs/providers/php.md](docs/providers/php.md) |
| Swift | `swift` | sourcekit-lsp | [docs/providers/swift.md](docs/providers/swift.md) |
| Kotlin | `kotlin` | kotlin-language-server | [docs/providers/kotlin.md](docs/providers/kotlin.md) |
| Scala | `scala`, `sbt` | metals | [docs/providers/scala.md](docs/providers/scala.md) |
| Zig | `zig`, `zir` | zls | [docs/providers/zig.md](docs/providers/zig.md) |
| Haskell | `haskell`, `lhaskell` | haskell-language-server | [docs/providers/haskell.md](docs/providers/haskell.md) |
| Unison | `unison` | ucm (running UCM over TCP) | [docs/providers/unison.md](docs/providers/unison.md) |
| OCaml | `ocaml`, `ocaml.interface`, `ocamllex`, `menhir`, `dune` | ocaml-lsp | [docs/providers/ocaml.md](docs/providers/ocaml.md) |
| Erlang | `erlang` | erlang-ls | [docs/providers/erlang.md](docs/providers/erlang.md) |
| Elixir | `elixir`, `eelixir`, `heex` | elixir-ls (lexical / next-ls opt-in) | [docs/providers/elixir.md](docs/providers/elixir.md) |
| Clojure | `clojure`, `edn` | clojure-lsp | [docs/providers/clojure.md](docs/providers/clojure.md) |
| Lua | `lua` | lua-language-server | [docs/providers/lua.md](docs/providers/lua.md) |
| Bash / Shell | `sh`, `bash` | bash-language-server | [docs/providers/bash.md](docs/providers/bash.md) |
| R | `r`, `rmd` | r-languageserver (air opt-in) | [docs/providers/r.md](docs/providers/r.md) |
| Perl | `perl` | perlnavigator | [docs/providers/perl.md](docs/providers/perl.md) |
| D | `d` | serve-d | [docs/providers/d.md](docs/providers/d.md) |
| Julia | `julia` | julia-lsp | [docs/providers/julia.md](docs/providers/julia.md) |
| Crystal | `crystal` | crystalline | [docs/providers/crystal.md](docs/providers/crystal.md) |
| Nim | `nim` | nimlangserver | [docs/providers/nim.md](docs/providers/nim.md) |
| Elm | `elm` | elm-language-server | [docs/providers/elm.md](docs/providers/elm.md) |
| V | `vlang`, `v` | v-analyzer | [docs/providers/v.md](docs/providers/v.md) |
| Odin | `odin` | ols | [docs/providers/odin.md](docs/providers/odin.md) |
| Gleam | `gleam` | gleam (built-in) | [docs/providers/gleam.md](docs/providers/gleam.md) |
| Racket | `racket`, `scheme` | racket-langserver | [docs/providers/racket.md](docs/providers/racket.md) |
| PureScript | `purescript` | purescript-language-server | [docs/providers/purescript.md](docs/providers/purescript.md) |
| Ada | `ada` | ada-language-server | [docs/providers/ada.md](docs/providers/ada.md) |
| Hare | `hare` | hare-lsp | [docs/providers/hare.md](docs/providers/hare.md) |
| Groovy | `groovy` | groovy-language-server | [docs/providers/groovy.md](docs/providers/groovy.md) |
| ReScript | `rescript` | rescript-language-server | [docs/providers/rescript.md](docs/providers/rescript.md) |
| Vala | `vala` | vala-language-server | [docs/providers/vala.md](docs/providers/vala.md) |
| Roc | `roc` | roc_language_server | [docs/providers/roc.md](docs/providers/roc.md) |
| Fish | `fish` | fish-lsp | [docs/providers/fish.md](docs/providers/fish.md) |
| Nushell | `nu` | nushell (`nu --lsp`) | [docs/providers/nushell.md](docs/providers/nushell.md) |
| Grain | `grain` | grain (`grain lsp`) | [docs/providers/grain.md](docs/providers/grain.md) |
| Common Lisp | `lisp` | cl-lsp (SLIME/Sly) | [docs/providers/commonlisp.md](docs/providers/commonlisp.md) |
| Pascal | `pascal` | pasls | [docs/providers/pascal.md](docs/providers/pascal.md) |
| HTML | `html` | html-lsp (+emmet/tailwind) | [docs/providers/html.md](docs/providers/html.md) |
| CSS / SCSS / LESS | `css`, `scss`, `less`, `sass` | css-lsp (+stylelint/tailwind) | [docs/providers/css.md](docs/providers/css.md) |
| JSON | `json`, `jsonc` | json-lsp | [docs/providers/json.md](docs/providers/json.md) |
| YAML | `yaml` | yaml-language-server | [docs/providers/yaml.md](docs/providers/yaml.md) |
| TOML | `toml` | taplo | [docs/providers/toml.md](docs/providers/toml.md) |
| Markdown | `markdown` | marksman | [docs/providers/markdown.md](docs/providers/markdown.md) |
| XML | `xml`, `xsd`, `xsl`, `svg` | lemminx | [docs/providers/xml.md](docs/providers/xml.md) |
| GraphQL | `graphql` | graphql-language-service-cli | [docs/providers/graphql.md](docs/providers/graphql.md) |
| Dockerfile | `dockerfile` | dockerfile-language-server | [docs/providers/dockerfile.md](docs/providers/dockerfile.md) |
| Terraform / HCL | `terraform`, `hcl` | terraform-ls | [docs/providers/terraform.md](docs/providers/terraform.md) |
| Nix | `nix` | nil | [docs/providers/nix.md](docs/providers/nix.md) |
| SQL | `sql`, `mysql`, `plsql` | sqls | [docs/providers/sql.md](docs/providers/sql.md) |
| Protocol Buffers | `proto` | protols | [docs/providers/proto.md](docs/providers/proto.md) |
| Helm | `helm` | helm-ls | [docs/providers/helm.md](docs/providers/helm.md) |
| Ansible | `yaml.ansible`, `ansible` | ansible-language-server | [docs/providers/ansible.md](docs/providers/ansible.md) |
| Svelte | `svelte` | svelte-language-server (+emmet/tailwind) | [docs/providers/svelte.md](docs/providers/svelte.md) |
| Vue | `vue` | vue-language-server (Volar) | [docs/providers/vue.md](docs/providers/vue.md) |
| Astro | `astro` | astro-language-server | [docs/providers/astro.md](docs/providers/astro.md) |
| Twig | `twig` | twiggy | [docs/providers/twig.md](docs/providers/twig.md) |
| Fortran | `fortran` | fortls | [docs/providers/fortran.md](docs/providers/fortran.md) |
| COBOL | `cobol` | superbol (from PATH) | [docs/providers/cobol.md](docs/providers/cobol.md) |
| MATLAB / Octave | `matlab`, `octave` | matlab-language-server | [docs/providers/matlab.md](docs/providers/matlab.md) |
| Tcl | `tcl` | tclsp | [docs/providers/tcl.md](docs/providers/tcl.md) |
| Solidity | `solidity` | nomicfoundation-solidity-language-server | [docs/providers/solidity.md](docs/providers/solidity.md) |
| Prolog | `prolog` | swipl (lsp_server) | [docs/providers/prolog.md](docs/providers/prolog.md) |
| PowerShell | `ps1` | powershell-editor-services | [docs/providers/powershell.md](docs/providers/powershell.md) |
| Assembly | `asm`, `nasm` | asm-lsp | [docs/providers/assembly.md](docs/providers/assembly.md) |
| Jsonnet | `jsonnet`, `libsonnet` | jsonnet-language-server | [docs/providers/jsonnet.md](docs/providers/jsonnet.md) |
| CUE | `cue` | cuelsp | [docs/providers/cue.md](docs/providers/cue.md) |
| Starlark / Bazel | `bzl`, `starlark` | starpls | [docs/providers/starlark.md](docs/providers/starlark.md) |
| Nginx | `nginx` | nginx-language-server | [docs/providers/nginx.md](docs/providers/nginx.md) |
| Vimscript | `vim` | vim-language-server | [docs/providers/vim.md](docs/providers/vim.md) |
| LaTeX | `tex`, `bib`, `plaintex` | texlab | [docs/providers/latex.md](docs/providers/latex.md) |
| CMake | `cmake` | cmake-language-server | [docs/providers/cmake.md](docs/providers/cmake.md) |

### Companion servers

Some LSP servers belong to no single language — they **co-attach** across the filetypes of many
providers. `lvim-lang` registers these through the same additive seam a provider's server uses (so
several clients attach to one buffer), keyed by their own cross-provider filetype list. A
project-scoped companion only starts where its marker exists (it is otherwise silently skipped).

| Companion | Mason | Co-attaches to | Project marker |
| --- | --- | --- | --- |
| Emmet | emmet-language-server | html, css/scss/less/sass, jsx/tsx, vue, svelte, astro | — (always) |
| Tailwind CSS | tailwindcss-language-server | html, css/scss/less/sass, js/jsx/ts/tsx, vue, svelte, astro | `tailwind.config.*` / `postcss.config.*` |
| Stylelint | stylelint-lsp | css, scss, less, sass | — (always) |
| Angular | angular-language-server | typescript, html | `angular.json` / `project.json` / `nx.json` |

Each is fully configurable under `companions` — enable/disable, change `filetypes`, `cmd`, `settings`,
or add your own:

```lua
require("lvim-lang").setup({
    companions = {
        ["stylelint-lsp"] = { enabled = false }, -- turn one off
        ["my-companion"] = { -- add your own
            mason = "some-language-server",
            cmd = { "some-language-server", "--stdio" },
            filetypes = { "html", "css" },
            require_root = true,
            root_patterns = { "some.config.js" },
        },
    },
})
```

## Install

Install with the ecosystem's own **lvim-installer**, or with Neovim's native `vim.pack`:

```lua
vim.pack.add({ "https://github.com/lvim-tech/lvim-lang" })
require("lvim-lang").setup({})
```

## Configuration

`setup()` merges your options into the live config in place; **everything is overridable** (your
`setup()` values always win over the defaults). Below are the shared **core** options; each
provider's full `providers.<name>` block is documented on its own page (linked above).

```lua
require("lvim-lang").setup({
    -- Master switch; when false no provider activates.
    enabled = true,

    -- Shared dev-log panel. `layout = nil` inherits the global `layout` below; set it to override
    -- the placement for this panel only. A `:LvimLang log <token>` wins over both.
    dev_log = {
        layout = nil, -- nil = inherit config.layout; "bottom"|"top"|"area"|"float"|"right"|"left"
        height = 15, -- rows for a horizontal placement (bottom/top/area)
        width = 60, -- columns for a vertical placement (right/left)
        max_lines = 5000,
        focus_on_open = false,
        notify_errors = true,
        -- filter = function(line) return true end,  -- return false to drop a line
    },

    -- Notification-driven decorations (closing labels, …).
    decorations = { enabled = true },

    -- Project-local config under the unified ".lvim/<plugin>/" namespace.
    project = { dir = ".lvim", run_file = "lang/run.lua" },

    -- Whether a provider contributes a statusline segment.
    statusline = true,

    -- GLOBAL default placement for lvim-lang panels (each panel may override with its own `layout`;
    -- a command token wins over both). "area" docks in the lvim-msgarea zone when available.
    layout = "bottom", -- "bottom" | "top" | "area" | "float" | "right" | "left"

    -- Generic core UI icons (Nerd Font). Per-language icons live in the provider block.
    icons = {
        run_config = "󰐊",
    },

    -- Per-language option blocks (see each provider's page).
    providers = {
        -- dart   = { … },   -- docs/providers/dart.md
        -- go     = { … },   -- docs/providers/go.md
        -- rust   = { … },   -- docs/providers/rust.md
        -- python = { … },   -- docs/providers/python.md
        -- typescript = { … },   -- docs/providers/typescript.md
        -- cpp    = { … },   -- docs/providers/cpp.md
        -- java   = { … },   -- docs/providers/java.md
        -- csharp = { … },   -- docs/providers/csharp.md
        -- fsharp = { … },   -- docs/providers/fsharp.md
        -- scala  = { … },   -- docs/providers/scala.md
        -- ruby   = { … },   -- docs/providers/ruby.md
        -- zig    = { … },   -- docs/providers/zig.md
        -- unison = { … },   -- docs/providers/unison.md
        -- erlang = { … },   -- docs/providers/erlang.md
        -- elixir = { … },   -- docs/providers/elixir.md
        -- ocaml  = { … },   -- docs/providers/ocaml.md
        -- haskell = { … },   -- docs/providers/haskell.md
    },
})
```

## Commands

`:LvimLang <sub> [args]` — core subcommands, plus the active buffer's provider subcommands (see the
provider pages). Completion offers the core subs merged with the current buffer's provider commands.

| Command | Description |
| --- | --- |
| `:LvimLang status` | Enabled state and registered providers |
| `:LvimLang providers` | List registered providers |
| `:LvimLang toolchain` | Resolve and report the active provider's toolchain |

## Run configurations

Named run configs live in `.lvim/lang/run.lua` — a pure-data file returning a list. `:LvimLang
config` picks the active one (remembered per project); `:LvimLang run` applies it. The fields a
config carries are provider-specific (see each provider's page).

## Statusline

`require("lvim-lang").status()` returns the active provider's segment (toolchain / run state /
active run config) for the current buffer — drop it into your statusline.

## Health

`:checkhealth lvim-lang` reports the core state, ecosystem dependencies, and each provider's own
checks (toolchain resolution).
