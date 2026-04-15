# Beam

Beam is a terminal text editor written in Zig. It embeds QuickJS so the editor can be extended with plugins and scripting, including TypeScript plugins that are transpiled and loaded at runtime.

## What Beam Is For

Beam aims to be a fast, scriptable editor for the terminal:

- core editing, motion, and buffer management live in Zig
- configuration is read from a TOML file
- plugins can register commands, react to events, and interact with files and buffers

## Repository Layout

- `src/main.zig` - process entry point
- `src/editor.zig` - editor runtime, command dispatch, and UI behavior
- `src/config.zig` - TOML config parsing and defaults
- `src/buffer.zig` - buffer editing logic
- `src/plugin.zig` - plugin loading and the QuickJS bridge
- `src/qjs_wrap.c` / `src/qjs_wrap.h` - C helpers for QuickJS integration
- `examples/beam.toml` - example configuration
- `examples/plugins/hello.ts` - sample plugin

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

## Configuration

The example config in `examples/beam.toml` shows the supported top-level sections:

- `[editor]` for editor behavior such as tab width, line numbers, status bar settings, theme, and appearance
- `[plugins]` for plugin loading options
- `[keymap]` for command remapping

Key defaults to know:

- config file default: `beam.toml`
- plugin directory default: `.beam/plugins`
- plugin auto-start default: enabled

The sample config enables the `hello` plugin. To use it as-is, place the plugin file under the configured plugin directory, for example:

```sh
mkdir -p .beam/plugins
cp examples/plugins/hello.ts .beam/plugins/hello.ts
```

Beam will load plugins from the configured plugin directory and start any enabled plugins when auto-start is on.

## Plugins

Plugins run through QuickJS and can:

- register commands
- listen for editor events
- log messages or set the status line
- read and write files
- open files or splits
- request the editor to quit

See `examples/plugins/hello.ts` for a minimal plugin that reacts to buffer-open events and registers a command.

## Contributing

Please keep changes small and focused. When behavior changes, add or update tests near the code that changed, especially in `src/editor.zig`, `src/config.zig`, or `src/plugin.zig`.

Before sending changes, make sure the project still passes:

- `zig build test`
- `zig build run -- --help`

Please avoid editing generated artifacts or vendored third-party code unless the task explicitly requires it. In particular, keep changes out of `zig-out/` and treat `deps/quickjs_clean` as upstream code.

If you are changing config keys, commands, or plugin behavior, update the docs and examples together so they stay in sync.

## License

Beam is licensed under the Apache License, Version 2.0. See [`LICENSE`](/Volumes/T7%20Shield/Files/OSS/Beam/LICENSE) for the full text.
