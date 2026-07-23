# GDScript / Godot

A declarative Tier 3 provider (game / scripting) — data record in `lvim-lang.providers.registry.gdscript`. The LSP and debug adapter are served by a RUNNING Godot editor over TCP (LSP 6005 / DAP 6006) — a bespoke server module + an inline DAP adapter connect to them. gdformat / gdlint (gdtoolkit) format and lint. GUT is the test framework.

## LSP

`gdscript` — a TCP connection to the Godot editor's built-in LSP (127.0.0.1:6005; the editor must be open on the project). Bespoke `servers/gdscript.lua` (same mechanism as Unison). Host/port overridable via `providers.gdscript.lsp.servers.gdscript.{host,port}`.

## Per-filetype catalog

| Filetype | Formatters | Linters | Debuggers | Defaults |
| --- | --- | --- | --- | --- |
| `gdscript` | gdformat | gdlint | (Godot) | opt-in |

## Commands

| Command | Description |
| --- | --- |
| (build via lvim-build) | `gdformat --check` / `gdlint` |

## Debugging

Godot exposes a Debug Adapter on `127.0.0.1:6006` while the editor is open; the provider connects to it (no process launched, like the LSP). Config: `Launch (Godot editor)`.

## Testing

`lvim-test` runs **GUT** — `godot --headless -s addons/gut/gut_cmdln.gd -gexit` over `test_*.gd` files (suite-granular; needs Godot + the GUT addon vendored in the project).
