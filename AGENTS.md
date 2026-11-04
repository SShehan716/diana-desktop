# Repository Guidelines

## Project Structure & Module Organization

Diana is a native macOS reminder app built as a Swift package with no external dependencies.

- `Sources/DianaApp/`: SwiftUI views, desktop panel, rendering, speech, and notifications.
- `Sources/DianaApp/Resources/Models/`: the six runtime USDZ character animations.
- `Sources/DianaCore/`: models, recurrence, persistence, conflict detection, voice parsing, and the Ollama client.
- `Tests/DianaCoreTests/`: unit tests for scheduling, persistence, speech text, conflicts, and confirmation rules.
- `Tests/DianaAppTests/`: wake listening and microphone lifecycle tests using simulated input.
- `Config/`: application metadata and icon.
- `scripts/`: app packaging and icon generation.
- `assets/diana/`: asset documentation and clip timing (`animations.json`). Original Blender and texture working files stay local.

Keep logic that does not need AppKit or SwiftUI in `DianaCore` so it stays unit-testable.

Use the project-level `.Codex/` directory for project-specific agent definitions, context, memory, and settings. It is ignored by Git. Do not store this project's configuration in `~/.Codex/`.

## Build, Test, and Development Commands

Requires macOS 15 or later and Xcode 16 or later. Run from the project root:

```sh
swift test
scripts/build.sh debug
scripts/build.sh
open build/Diana.app
xcrun swift-format lint --strict --recursive Sources Tests Package.swift scripts/create-icon.swift
```

Set `DIANA_SIGN_IDENTITY`, or put the identity in `.Codex/signing-identity`, to keep microphone and speech permissions across rebuilds. Without it, the build is ad-hoc signed. Keep `README.md` in sync when commands change.

## Coding Style & Naming Conventions

Swift with four-space indentation, formatted by the committed `.swift-format` configuration; the lint command above must pass. Use descriptive names, keep indentation consistent, and avoid unrelated formatting changes. Follow neighboring code.

## Testing Guidelines

Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) and run with `swift test`. Cover normal operation and relevant failure cases, and name tests after the behavior they verify. Microphone and speech behavior is tested with simulated input; do not depend on real audio hardware. Report any checks that could not be run.

## Commit & Pull Request Guidelines

Use concise, imperative commit subjects, such as `Improve Hey Diana microphone lifecycle`. Keep changes focused. Pull requests should explain the change, describe validation, link related issues when applicable, and include screenshots for visible interface changes. See `CONTRIBUTING.md` for the contribution process and license terms.

## Security & Configuration

Keep secrets, signing identities, and local credentials out of version control; `.gitignore` already excludes common key, certificate, and provisioning files. Do not commit reminder data (`reminders.json`), backups, recordings, or logs. Only commit assets you have the rights to distribute under the project license.
