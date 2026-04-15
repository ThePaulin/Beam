# AGENTS.md

## Project Shape
- Beam is a Zig terminal editor that embeds QuickJS for plugins and scripting.
- The main application entrypoint lives in [`src/main.zig`](./src/main.zig).
- Editor orchestration lives in [`src/editor.zig`](./src/editor.zig), with focused editor modules in [`src/editor/render.zig`](./src/editor/render.zig), [`src/editor/bindings.zig`](./src/editor/bindings.zig), and [`src/editor/commands.zig`](./src/editor/commands.zig).
- Config parsing and defaults live in [`src/config.zig`](./src/config.zig).
- Buffer editing behavior lives in [`src/buffer.zig`](./src/buffer.zig).
- Plugin loading and the QuickJS bridge live in [`src/plugin.zig`](./src/plugin.zig), [`src/qjs_wrap.c`](./src/qjs_wrap.c), and [`src/qjs_wrap.h`](./src/qjs_wrap.h).
- Vendored QuickJS sources are in [`deps/quickjs_clean`](./deps/quickjs_clean). Treat this as third-party code unless the task explicitly requires touching it.

## Working Style
- Make small, focused changes and keep the edit surface narrow.
- Prefer putting new editor logic into the smallest relevant module:
  - rendering, theme, status, and text-width helpers in `src/editor/render.zig`
  - normal-mode bindings and leader lookup in `src/editor/bindings.zig`
  - command parsing and command-string helpers in `src/editor/commands.zig`
  - orchestration, event flow, and cross-module wiring in `src/editor.zig`
- Prefer updating tests close to the behavior you changed. Some coverage still lives in `src/editor.zig`, but new helper behavior should be tested beside the module that owns it.
- When changing config keys, commands, or help text, update the user-facing docs and example config together so they stay aligned.
- Keep generated artifacts out of source changes. Do not edit `zig-out/` by hand.
- Use ASCII by default. Only introduce Unicode when it is already part of the file or required by the feature.

## Git Workflow
- The principal branch is `main`.
- Day-to-day integration happens on `dev`.
- Always branch from `dev` when starting a new task.
- Keep task branches short-lived and task-specific.
- Avoid committing unrelated changes together unless the user explicitly asks for that.
- When the task is done, request approval before committing changes.
- After the changes are committed, request approval before opening a PR to update `dev`.
- After approval to continue, switch to `dev`, pull the latest changes from the remote, return to the task branch, merge `dev` into the task branch, resolve conflicts if any, push the task branch to the remote, and only then create the PR into `dev` on GitHub.
- After the PR is open, ask for approval before merging it.
- Prefer non-destructive Git commands. Do not reset, force-push, or rewrite history unless the user explicitly approves it.
- Check `git status` before and after each meaningful Git step so the working tree stays understandable.

## Build And Run
- Always build and run the project after each change, then fix any errors before considering the task done.
- Use `zig build test` for the primary verification pass.
- Use `zig build run -- --help` as the safe non-interactive smoke test for the executable.
- If Zig tries to write to an unwritable global cache, rerun with `ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache ZIG_LOCAL_CACHE_DIR=.zig-cache`.
- If a change is meant to affect interactive behavior, do an additional manual run in a terminal once the build is clean.
- If a build or test fails, fix the failure immediately before moving on.

## Testing Expectations
- Add or adjust tests when behavior changes; this project relies heavily on unit tests in the Zig source files.
- Prefer regression tests for parsing, command dispatch, buffer operations, and plugin host behavior.
- Keep the existing smoke checks in the loop for editor refactors: `zig build test` and `zig build run -- --help`.
- If you touch the C bridge or plugin runtime, verify both Zig-side tests and the executable smoke test.

## Repo Conventions
- `build.zig` is the source of truth for build steps, linked libraries, and run/test targets.
- Example config lives in [`examples/beam.toml`](./examples/beam.toml); keep it in sync with supported defaults.
- Plugin examples live in [`examples/plugins`](./examples/plugins). Use them as a reference when changing plugin behavior.
- Keep logging and debug output minimal unless it helps diagnose a real issue.
- Avoid unnecessary churn in vendored dependency files under `deps/`.

## Good Handoff Checklist
- Confirm the project builds.
- Confirm the test suite passes.
- Confirm the executable smoke test exits cleanly.
- Note any remaining risk, especially if a change was not covered by tests.
