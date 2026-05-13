#!/bin/zsh
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/soichiro-nitta/spaceguard/main}"
ROOT="$(cd "$(dirname "$0")" 2>/dev/null && pwd || pwd)"
SOURCE="$ROOT/SpaceGuard.swift"

if [[ ! -f "$SOURCE" ]]; then
  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR"' EXIT
  SOURCE="$WORKDIR/SpaceGuard.swift"
  /usr/bin/curl -fsSL "$REPO_RAW_BASE/SpaceGuard.swift" -o "$SOURCE"
fi

mkdir -p "$PREFIX/bin"
/usr/bin/swiftc "$SOURCE" -o "$PREFIX/bin/spaceguard" -framework AppKit -framework CoreGraphics

echo "installed: $PREFIX/bin/spaceguard"
