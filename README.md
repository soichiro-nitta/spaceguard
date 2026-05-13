# SpaceGuard

SpaceGuard is a small macOS CLI for AI agents that need to keep browser or desktop automation inside the same macOS Desktop/Space as the current Codex thread.

It detects the Codex window for the current `CODEX_THREAD_ID`, maps that window to the macOS Space data in `com.apple.spaces`, and returns the target desktop as text or JSON.

This project intentionally uses private/undocumented macOS Spaces data. Treat it as a pragmatic local guardrail for agent workflows, not as a stable public macOS API.

## Install

### Homebrew

```sh
brew tap soichiro-nitta/tap
brew install --HEAD spaceguard
```

The Homebrew formula lives in [`soichiro-nitta/homebrew-tap`](https://github.com/soichiro-nitta/homebrew-tap). The `Formula/spaceguard.rb` copy in this repository is kept as the source formula.

### Local development install

One-line install:

```sh
curl -fsSL https://raw.githubusercontent.com/soichiro-nitta/spaceguard/refs/heads/main/install.sh | zsh
```

From a clone:

```sh
git clone https://github.com/soichiro-nitta/spaceguard.git
cd spaceguard
./install.sh
```

`install.sh` compiles the CLI to `~/.local/bin/spaceguard`. `build.sh` additionally creates `build/SpaceGuard.app` for the optional menu bar helper.

## First run

SpaceGuard needs macOS Accessibility permission because it reads the Codex window geometry through Accessibility.

1. Run `spaceguard detect --json` from inside Codex.
2. If macOS asks for permission, allow the terminal/Codex host under System Settings > Privacy & Security > Accessibility.
3. Run the command again.

## Codex setup

Register the SpaceGuard plugin with Codex:

```sh
spaceguard setup-codex
```

This installs or updates the plugin at `~/plugins/spaceguard` and registers it in `~/.agents/plugins/marketplace.json`. It does not edit your personal Codex rules.

To preview the changes first:

```sh
spaceguard setup-codex --dry-run
```

To also add a managed SpaceGuard rule block to `~/.codex/AGENTS.md`:

```sh
spaceguard setup-codex --with-agents-rule
```

This mode asks before each step and backs up `~/.codex/AGENTS.md` before changing it. To run without prompts:

```sh
spaceguard setup-codex --with-agents-rule --yes
```

## Uninstall

Preview what SpaceGuard would remove:

```sh
spaceguard uninstall --dry-run
```

Remove SpaceGuard-owned files and Codex registration:

```sh
spaceguard uninstall
```

`uninstall` removes `~/.local/bin/spaceguard`, `~/.spaceguard/`, `~/plugins/spaceguard`, and the `spaceguard` entry from `~/.agents/plugins/marketplace.json`.

If a managed SpaceGuard block exists in `~/.codex/AGENTS.md`, SpaceGuard prints the exact block first and asks before removing only that block. It never deletes the whole `AGENTS.md` file. To keep the rule block:

```sh
spaceguard uninstall --keep-agents-rule
```

## CLI

```sh
spaceguard detect --json
spaceguard windows --json
spaceguard assert --app "Google Chrome"
spaceguard setup-codex
spaceguard uninstall
spaceguard menubar
```

`detect --json` is the main command for Codex rules. It writes the latest detection to `~/.spaceguard/last-detection.json`.

Example:

```json
{
  "ok": true,
  "confidence": "high",
  "threadName": "spaceguard作成",
  "space": {
    "desktopName": "デスクトップ3",
    "desktopIndex": 3,
    "internalSpaceId": 5
  }
}
```

## Recommended Codex Rule

Add a rule like this to your Codex instructions:

```md
Before using Computer Use or Chrome automation, run `spaceguard detect --json`.
Only operate in the detected `space.desktopName` when `confidence` is `high` or `cached-high`.
If detection fails or confidence is lower than that, do not operate existing windows from another Space; ask the user or create a new window only after the target Space is clear.
```

## Codex plugin

This repository is also a Codex plugin. The plugin does not install the CLI by itself; install the CLI first, then run `spaceguard setup-codex`.

The plugin provides the `spaceguard-safe-desktop-operation` skill. It teaches Codex to run `spaceguard detect --json` before Chrome, Computer Use, or desktop app operations.

For users who want maximum certainty, keep a short global rule as well:

```md
Before using Chrome, Computer Use, or macOS desktop automation, use the SpaceGuard plugin workflow.
```

## Menu bar helper

`spaceguard menubar` starts an optional menu bar helper. It is only for visibility. The CLI remains the source of truth for agent workflows.
