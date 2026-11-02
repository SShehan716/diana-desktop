# Repository Guidelines

## Project Structure & Module Organization

This project directory currently has no application code, tests, assets, or build configuration. Establish the structure alongside the first implementation and update this guide to match it. Group source files by feature, keep tests near the code they exercise or in a dedicated test directory, and give shared assets a clearly named location. These are organizational recommendations; no directory layout is established yet.

Use the project-level `.Codex/` directory for project-specific agent definitions, context, memory, and settings. Do not store this project's configuration in `~/.Codex/`.

## Build, Test, and Development Commands

No build, test, or local development commands are configured. When introducing the application toolchain, document the exact setup, run, build, and test commands in a root `README.md`. Include required tool versions and environment setup. Verify each documented command from the project root before submitting it.

## Coding Style & Naming Conventions

No language, formatter, or linter has been selected. Follow the idiomatic conventions of the chosen language and commit formatter or linter configuration with the initial implementation. Keep indentation consistent within each file, use descriptive names, and avoid unrelated formatting changes. Once conventions exist, follow neighboring code.

## Testing Guidelines

No testing framework or coverage threshold is configured. Add automated tests with executable behavior, covering normal operation and relevant failure cases. Name tests after the behavior they verify and follow the selected framework's discovery rules. Document how to run the suite and report any checks that could not be completed.

## Commit & Pull Request Guidelines

No Git history is available to establish existing commit conventions. Use concise, imperative commit subjects, such as `Add reminder scheduling`. Keep changes focused. Pull requests should explain the change, describe validation, link related issues when applicable, and include screenshots for visible interface changes.

## Security & Configuration

Keep secrets and local credentials out of version control. Document required configuration using placeholders, and exclude generated output and machine-specific files when adding `.gitignore`.
