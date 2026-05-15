---
name: spaceguard-safe-desktop-operation
description: Use when controlling Chrome, Computer Use, or macOS desktop apps from Codex while the user uses macOS Spaces. Detect the current Codex thread's Desktop with `spaceguard detect --json` before operating windows.
---

# SpaceGuard Safe Desktop Operation

Use this skill before any Codex Chrome Extension, Computer Use, or macOS desktop app operation that could touch an existing window.

## Prerequisite

SpaceGuard CLI must be installed and available as `spaceguard`.

If it is missing, tell the user to install it:

```sh
brew tap soichiro-nitta/tap
brew install --HEAD spaceguard
```

## Required Flow

1. Run `spaceguard detect --json`.
2. Continue only when the JSON has `ok: true` and `confidence` is `high`, `thread-bound`, `cached-high`, or `fallback-active-space`.
3. Treat `space.desktopName` as the only target Desktop/Space for this turn.
4. When multiple Codex or Chrome windows may be open, run `spaceguard windows --json` after `detect --json` and confirm it reports the same `threadId`, same `space.desktopIndex`, and `source: "current-thread-detection"` or a clearly recent `source: "recent-last-detection"`.
5. State the detected Desktop and confidence briefly before using Chrome or Computer Use.
6. Before operating a named app when practical, run `spaceguard assert --app "<App Name>"`.
7. If detection fails, confidence is lower, `windows --json` disagrees with `detect --json`, or the target app is not in the detected Desktop, do not operate an existing window from another Space.
8. If detection reports that multiple Codex windows are open and no thread/window hint is available, stop unless a `cached-high` result for the same thread or a `fallback-active-space` result is returned.
9. Do not manually bind a Desktop. When detection is ambiguous, ask the user to bring the target Codex thread into view and run `spaceguard detect --json` again.
10. Run SpaceGuard commands sequentially. Do not call `detect`, `windows`, `assert`, or `open-url` in parallel, because they read or update the current thread's detection state.

## Command Map

- `spaceguard detect --json`: Use first. Detects the Desktop/Space for the current Codex thread.
- `spaceguard windows --json`: Use when you need to inspect windows in the detected Desktop.
- `spaceguard assert --app "<App Name>"`: Use before touching an app. Confirms the app has a window in the detected Desktop.
- `spaceguard open-url --app "Google Chrome" "<url>"`: Use to create a background Chrome tab in the detected Desktop.
- `spaceguard open-url --activate --app "Google Chrome" "<url>"`: Use only when foregrounding the target Chrome window is acceptable.
- `spaceguard status`: Use to inspect the current thread's saved target Space and detection state.
- `spaceguard clear`: Use to discard the current thread's saved target Space and detection cache.
- `spaceguard clear --all-stale`: Use to remove stale saved thread Spaces older than the retention window.

## Operating Rules

- The target Space is the Space containing the Codex window for the current thread, not necessarily the Space the user is currently viewing.
- A `high` detection persists the current thread's target Space. Later `windows`, `assert`, and `open-url` prefer that saved thread Space.
- `thread-bound` means SpaceGuard reused the saved target Space for the current Codex thread after confirming the saved Codex window still exists in that Space.
- With multiple Codex windows open, do not trust `thread-bound` by itself. Confirm `detect --json` and `windows --json` agree before touching Chrome or other desktop apps.
- `cached-high` means SpaceGuard reused a `high` result from the same thread only after confirming the cached Codex window still exists in the same Desktop and the cache is recent. Treat it as the current thread's target Space, but re-run `detect` if the user says the Codex window moved.
- `fallback-active-space` is weaker than `high` and can reflect the currently visible Desktop. It is not persisted as the current thread's target Space.
- Do not bring forward, move, or operate a window that is only known to exist in another Space.
- Keep this skill focused on Space detection and target-window selection.
- When opening a new Chrome URL for a visual/browser check, prefer `spaceguard open-url --app "Google Chrome" "<url>"` after `detect` and `assert`. Do not start with Codex Chrome Extension `browser.tabs.new()` when the user may be working in another Space.
- When multiple Chrome windows are open, use `spaceguard open-url --app "Google Chrome" "<url>"` for the initial URL handoff so the URL lands in the Chrome window inside the detected Desktop.
- If the task only asks to show a page to the user in the target Space, stop after `spaceguard open-url` succeeds.
- After `spaceguard open-url` succeeds, treat further tab selection, tab operation, tab groups, cleanup, DOM inspection, screenshots, clicks, and typing as Codex Chrome Extension or Chrome-skill responsibilities, not SpaceGuard responsibilities.
- Do not use SpaceGuard rules as the source of truth for Chrome tab lifecycle after the URL has been opened.
- Do not run `open-url`, `assert`, or `windows` from a stale detection created by another Codex thread. If SpaceGuard reports a thread mismatch, run `spaceguard detect --json` in the current thread or stop.
- `spaceguard open-url --activate --app "Google Chrome" "<url>"` brings the matched Chrome window in the detected Desktop forward and activates the new tab. Use it only after the target Desktop has been detected.
- After opening a Chrome URL, run `spaceguard windows` or `spaceguard assert --app "Google Chrome"` when practical to confirm the target Desktop still contains the Chrome window.
- If a new non-Chrome window is needed, create it only when you can verify it appears in the detected Space.
- If verification is ambiguous, stop and ask the user which window or Space should be used.

## Reporting Format

Before desktop automation, report a short line like:

```text
SpaceGuard: デスクトップ3 / confidence=high。ここにあるChromeだけを操作します。
```

Keep this report brief and do not paste the full JSON unless the user asks for it.
