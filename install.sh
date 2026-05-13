#!/bin/zsh
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
REPO="${REPO:-soichiro-nitta/spaceguard}"
REF="${REF:-main}"
REPO_RAW_BASE="${REPO_RAW_BASE:-}"
ROOT="$(cd "$(dirname "$0")" 2>/dev/null && pwd || pwd)"
SOURCE="$ROOT/SpaceGuard.swift"

if [[ ! -f "$SOURCE" ]]; then
  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR"' EXIT
  SOURCE="$WORKDIR/SpaceGuard.swift"
  if [[ -z "$REPO_RAW_BASE" ]]; then
    SHA="$(/usr/bin/curl -fsSL "https://api.github.com/repos/$REPO/commits/$REF" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])')"
    REPO_RAW_BASE="https://raw.githubusercontent.com/$REPO/$SHA"
  fi
  /usr/bin/curl -fsSL "$REPO_RAW_BASE/SpaceGuard.swift" -o "$SOURCE"
fi

mkdir -p "$PREFIX/bin"
/usr/bin/swiftc "$SOURCE" -o "$PREFIX/bin/spaceguard" -framework AppKit -framework CoreGraphics

echo "installed: $PREFIX/bin/spaceguard"
