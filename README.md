# Beam

Beam is a terminal text editor written in Zig. It is now native-first: the editor core owns timing, buffers, layout, rendering, and scheduling, while built-ins provide the main extension surface.

## What Beam Is For

Beam aims to be a fast editor for the terminal:

- core editing, motion, and buffer management live in Zig
- configuration is read from a TOML file
- built-in modules can register commands, react to events, and update editor state

## Repository Layout

- `src/main.zig` - process entry point
- `src/editor.zig` - editor runtime, command dispatch, and UI behavior
- `src/config.zig` - TOML config parsing and defaults
- `src/buffer.zig` - buffer editing logic
- `src/builtins.zig` - native built-in registry and event hooks
- `examples/beam.toml` - example configuration
- `examples/beam.toml` - sample configuration with a native built-in enabled

## Build And Run

All commands below are run from the repository root.

Build and run the test suite:

```sh
zig build test
```

Run the executable and print the built-in help:

```sh
zig build run -- --help
```

If Zig cannot write to the default cache locations, use:

```sh
ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache ZIG_LOCAL_CACHE_DIR=.zig-cache zig build test
```

## Quick Start

Clone the repository and enter it:

```sh
git clone <repo-url>
cd Beam
```

Run Beam with the default config search path:

```sh
zig build run
```

By default Beam looks for `beam.toml` in the current directory. You can point it at a different config file with `--config`:

```sh
zig build run -- --config examples/beam.toml
```

You can also open a file directly:

```sh
zig build run -- --config examples/beam.toml path/to/file.txt
```

If no config file is found, Beam falls back to built-in defaults.

## Editing Grammar

Beam's normal mode is built around composable motions and edits:

- basic cursor movement: `h j k l`
- line anchors: `0`, `^`, `$`, plus `g0`, `g^`, `g$`
- local find motions: `f/F/t/T`, repeated with `;` and `,`
- compound motion + operator edits: `dw`, `diw`, `d$`, `ciw`, `yap`
- repeat last change: `.`
- visual selections can be extended with compound motions too, for example `VG` selects from the current line to the end of the file

Beam keeps the motion and editing grammar intentionally small, but the goal is for the pieces above to compose cleanly.

## Configuration

The example config in `examples/beam.toml` shows the supported top-level sections:

- `[editor]` for editor behavior such as tab width, line numbers, status bar settings, theme, and appearance
- `[builtins]` for enabling compiled-in modules
- `[keymap]` for command remapping and the leader prefix
- `[keymap.leader]` for leader-prefixed normal-mode mappings

The `leader` value can be any byte sequence, and the `[keymap.leader]` table maps the keys that follow it to direct editor actions.
The sample config includes `x = "close_prompt"` so `leader x` asks before closing a split, tab, or buffer.

Key defaults to know:

- config file default: `beam.toml`
- leader default: `:`

The sample config enables the native `hello` built-in:

```sh
zig build run -- --config examples/beam.toml
```

## Built-Ins

Built-ins are compiled with Beam and can:

- register commands
- listen for editor events
- update the status line
- request host-owned actions through narrow native APIs

## Contributing

Please keep changes small and focused. When behavior changes, add or update tests near the code that changed, especially in `src/editor.zig`, `src/config.zig`, or `src/builtins.zig`.

Before sending changes, make sure the project still passes:

- `zig build test`
- `zig build run -- --help`

Please avoid editing generated artifacts or vendored third-party code unless the task explicitly requires it. In particular, keep changes out of `zig-out/` and treat `deps/quickjs_clean` as upstream code.

If you are changing config keys, commands, or built-in behavior, update the docs and examples together so they stay in sync.

## License

Beam is licensed under the Apache License, Version 2.0. See [`LICENSE`](/Volumes/T7%20Shield/Files/OSS/Beam/LICENSE) for the full text.
