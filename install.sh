#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"

mkdir -p "$PREFIX/bin"
/usr/bin/swiftc "$ROOT/SpaceGuard.swift" -o "$PREFIX/bin/spaceguard" -framework AppKit -framework CoreGraphics

echo "installed: $PREFIX/bin/spaceguard"
