#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/brew-upgrade"
test -f "$SCRIPT_FILE"
grep -q '^brew update$' "$SCRIPT_FILE"
grep -q '^  log_change "Installation" "Homebrew metadata" "Updated" "\$BREW_PREFIX" "Updated Homebrew metadata"$' "$SCRIPT_FILE"
grep -q '^brew bundle install --file="\$BREWFILE"$' "$SCRIPT_FILE"
grep -q '^entry_is_outdated() {$' "$SCRIPT_FILE"
grep -q '^  if entry_is_outdated "brew" "\$formula"; then$' "$SCRIPT_FILE"
grep -q '^    brew upgrade "\$formula"$' "$SCRIPT_FILE"
grep -q '^  if entry_is_outdated "cask" "\$cask"; then$' "$SCRIPT_FILE"
grep -q '^    brew upgrade --cask "\$cask"$' "$SCRIPT_FILE"
echo "Brew upgrade checks passed"
