#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BREWFILE="$ROOT/config/brew/Brewfile"
test -f "$BREWFILE"
grep -q 'brew "chezmoi"' "$BREWFILE"
grep -q 'brew "podman"' "$BREWFILE"
grep -q 'brew "podman-compose"' "$BREWFILE"
grep -q 'cask "iterm2"' "$BREWFILE"
grep -q 'cask "podman-desktop"' "$BREWFILE"
echo "Brewfile checks passed"
