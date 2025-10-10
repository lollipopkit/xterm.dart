# Agent Handbook

This guide keeps coding agents aligned with the expectations for `xterm.dart`. Review it before you begin a session and reference it whenever the workflow gets fuzzy.

## Quick-Start Checklist
- Read the latest system/developer instructions and the user's request; do not assume they match previous runs.
- Inspect the current sandbox context (cwd, sandbox mode, approval policy, network access) before issuing commands.
- For non-trivial work, draft or update a plan using the planner tool; skip planning only when the task is truly simple.
- Prefer read-only discovery first (`ls`, `rg`, `git status`) to understand repository state before modifying files.
- Confirm there are no unexpected local changes you need to preserve; never overwrite user edits that you did not make.

## Repository Primer
- Top level:
  - `lib/` is the package entry point. Public exports live in `core.dart`, `ui.dart`, `utils.dart`, `suggestion.dart`, `zmodem.dart`, and `xterm.dart`. Keep implementations inside `lib/src/`.
  - `bin/` contains CLI utilities (`xterm_bench.dart`, `xterm_dump.dart`) that should stay in sync with core APIs.
  - `example/` hosts the showcase Flutter app plus helper utilities under `example/lib/src/`.
  - `script/` is a scratchpad for experiments and one-off tooling; nothing here ships to users.
  - `media/` stores documentation assets, `rfc/` carries design discussions, and `CHANGELOG.md` + `AGENTS.md` document process.
  - `test/` mirrors source layout; `test/_fixture/` holds serialized data and goldens.
  - `xterm.js` vendors the JS backend—update alongside upstream changes.
- Inside `lib/src/` (implementation details):
  - `base/` — lightweight primitives (`disposable`, `observable`, `event`) that abstract platform glue.
  - `core/` — the terminal engine. Key areas:
    - `buffer/` manages scrollback lines, cell flags, ranges, and segmentation.
    - `escape/` parses and dispatches ANSI/VT sequences via `emitter`, `handler`, and `parser`.
    - `input/` covers keyboard handling, including the `keytab` parser/recorder helpers.
    - `mouse/` implements mouse modes, button mapping, and reporting.
    - Supporting files such as `state.dart`, `cursor.dart`, `reflow.dart`, and `snapshot.dart` orchestrate runtime state.
  - `ui/` — Flutter integration:
    - Paint pipeline (`painter.dart`, `render.dart`, `paragraph_cache.dart`, `char_metrics.dart`).
    - Interaction (`controller.dart`, `keyboard_listener.dart`, `pointer_input.dart`, `gesture/`, `shortcut/`).
    - Presentation (`terminal_theme.dart`, `palette_builder.dart`, `selection_mode.dart`, `terminal_text_style.dart`, `infinite_scroll_view.dart`).
  - `utils/` — shared helpers (`ascii`, `unicode_v11`, `lookup_table`, `circular_buffer`, debugging tools).
  - `terminal.dart` exposes the pure Dart engine; `terminal_view.dart` wraps it in a widget.
- Tests:
  - `test/src/core/` mirrors `lib/src/core/` with focused unit tests.
  - `test/src/utils/` owns helper coverage; `test/buffer/` and `test/frontend/` cover integration scenarios.
  - Golden assets reside under `test/src/_goldens/`; regenerate fixtures via provided scripts before committing.
- Examples:
  - `example/lib/main.dart` boots the demo app.
  - Additional flows (`debugger.dart`, `zmodem.dart`, `ssh.dart`, `mock.dart`, `suggestion.dart`) exercise optional integrations.

## Workflow Expectations
- Gather context before coding: skim relevant files, existing tests, and docs. Favor `rg` for searches; fall back to other tools only if unavailable.
- When using the plan tool, break work into at least two steps and update the plan after completing each step. Do not keep plans stale.
- Use shell commands via `shell` with `bash -lc` and always set `workdir`. Avoid `cd` sequences in commands unless required.
- Ask for clarification when requirements are ambiguous; otherwise make reasonable assumptions and state them in the final message.
- Validate assumptions early—run formatters/linters/tests only when meaningful for the change or if uncertainty remains.

## Editing Guardrails
- Default to ASCII in files unless the file already uses non-ASCII and it is required for the change.
- Prefer `apply_patch` for scoped edits. Use purposeful scripts or editors only when automation is clearly safer than manual patching.
- Never revert unrelated local changes or perform destructive git operations (`git reset --hard`, `git checkout --`) without explicit user direction.
- Keep comments concise and only when they clarify complex logic; avoid narrating straightforward code.
- When referencing files in conversation, provide clickable relative paths with line numbers (e.g., `lib/src/core/terminal.dart:42`).

## Coding Style & Naming
- Indent with two spaces. Use `UpperCamelCase` for types and `lowerCamelCase` for members.
- Keep platform abstractions in `lib/src/base` and utilities in `lib/src/utils` to maintain layering boundaries.
- Enforce metrics ceilings: cyclomatic complexity ≤20, nesting depth ≤5, and ≤50 SLoC per member. Split logic or extract helpers when you approach limits.
- Trailing commas belong on multi-line collection literals and parameter lists to keep diffs tidy.
- Document new public APIs with focused Dartdoc and update exports only once the API is ready for consumption.

## Build, Test, and Tooling Commands
- `flutter pub get` — Sync package and example dependencies after touching `pubspec.*`.
- `dart format .` — Format the repository prior to handing work back; fail fast if formatting breaks.
- `dart analyze --fatal-infos` — Run static analysis (with `dart_code_metrics`) before concluding a change or when touching shared code.
- `flutter test [path]` — Execute targeted or full test suites. Favor narrower runs when iterating quickly.
- `dart run bin/xterm_bench.dart` — Track performance drift for core changes; mention results in your final note if you ran it.
- `flutter run example/lib/main.dart -d macos` — Smoke test UI-related updates.

## Testing Expectations
- Mirror source layout in tests (`test/core/terminal_state_test.dart`). Name suites with the class under test to keep coverage maps clear.
- Prefer fakes or lightweight fixtures over platform channels; regenerate fixtures under `test/_fixture` with helper scripts and justify deltas when they change.
- Use `flutter test --coverage` periodically to watch for regressions; close notable gaps before merge when feasible.
- When you cannot run tests (e.g., sandbox limits), explain what was skipped and suggest how the user can verify.

## Documentation & Communication
- Update Markdown, examples, and changelogs when behavior, CLI flags, or public APIs shift.
- Provide concise, friendly final responses: lead with the change, cite touched files with line references, and summarize testing performed or skipped.
- Offer natural next steps (tests, commits, release checks) when relevant, using numbered lists for multiple suggestions.
- Do not paste large file dumps; reference paths instead. Highlight risks or follow-up questions before offering summaries.

## Commit & Pull Request Guidance
- Use Conventional Commits (`fix:`, `feat:`, `chore:`, `refactor:`) with subjects under ~60 characters and bodies wrapped at 72.
- Reference issues (e.g., `#123`) and add `BREAKING CHANGE:` blocks for external API shifts.
- Keep `CHANGELOG.md` in sync with any public-facing updates. Include motivation, verification steps (`dart analyze`, `flutter test`, benchmarks), and relevant screenshots or GIFs in PR descriptions.
- Rebase onto `master` after CI passes to keep history linear.

## Release & Maintenance Notes
- Target Dart `>=3.8.0` and Flutter `>=3.32.0`. When bumping dependencies, commit both `pubspec.yaml` and `pubspec.lock`, then rerun `flutter pub get` inside `example/` to refresh its lockfile.
- Preserve third-party notices in `LICENSE` and record new assets in `media/`.
- Re-run benchmark suites and ensure example apps launch cleanly before tagging a release.
- Keep `xterm.js` synchronized with upstream updates to avoid API drift. You can view it for reference but do not edit it directly.
