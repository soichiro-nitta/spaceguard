# SpaceGuard

SpaceGuard is a local macOS menu bar app for keeping AI/browser automation scoped to a bound macOS Space.

Current scope:

- Bind the Codex window in the target Space.
- Show the bound Space in the menu bar.
- List windows that belong to the bound Space.
- Provide a CLI for Codex rules: `status`, `windows`, `assert --app`.

This is a personal-use prototype. It reads macOS Spaces data from `com.apple.spaces`, which is not a stable public API.

