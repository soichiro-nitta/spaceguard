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
2. Continue only when the JSON has `ok: true` and `confidence` is `high`, `cached-high`, or `fallback-active-space`.
3. Treat `space.desktopName` as the only target Desktop/Space for this turn.
4. State the detected Desktop and confidence briefly before using Chrome or Computer Use.
5. Before operating a named app when practical, run `spaceguard assert --app "<App Name>"`.
6. If detection fails, confidence is lower, or the target app is not in the detected Desktop, do not operate an existing window from another Space.
7. If detection reports that multiple Codex windows are open and no thread/window hint is available, stop unless a `cached-high` result for the same thread or a `fallback-active-space` result is returned.
8. If the user explicitly says which Desktop contains the current Codex thread, run `spaceguard bind --desktop <n>` and treat that manual binding as the target for this turn.

## Operating Rules

- The target Space is the Space containing the Codex window for the current thread, not necessarily the Space the user is currently viewing.
- `cached-high` means SpaceGuard reused a `high` result from the same thread only after confirming the cached Codex window still exists in the same Desktop and the cache is recent. Treat it as the current thread's target Space, but re-run `detect` if the user says the Codex window moved.
- `fallback-active-space` is weaker than `high` and can reflect the currently visible Desktop. Use it only when it is reasonable for the current task, and prefer `spaceguard bind --desktop <n>` when the user can identify the correct Desktop.
- Do not bring forward, move, or operate a window that is only known to exist in another Space.
- Keep this skill focused on Space detection and target-window selection.
- When opening a new Chrome URL for a visual/browser check, prefer `spaceguard open-url --app "Google Chrome" "<url>"` after `detect` and `assert`. Do not start with Codex Chrome Extension `browser.tabs.new()` when the user may be working in another Space.
- After `spaceguard open-url` succeeds, use Codex Chrome Extension `browser.user.openTabs()` to find the opened URL and `browser.user.claimTab(tab)` to continue automation in that tab.
- For existing-tab selection, tab groups, finalization, and browser operation details after the target tab is claimed, follow the Codex Chrome Extension workflow and the user's global Chrome-operation rules.
- Do not use SpaceGuard rules as the source of truth for Chrome tab lifecycle after the tab has been opened and claimed.
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
