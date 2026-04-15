#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/brew-install"

test -f "$SCRIPT_FILE"
grep -q 'parse_brewfile_entries' "$ROOT/lib/shell/common.sh"
grep -q 'require_macos' "$SCRIPT_FILE"
grep -q 'process_brewfile' "$SCRIPT_FILE"
grep -q 'parse_brewfile_entries' "$SCRIPT_FILE"
grep -q 'brew install "\$entry_name"' "$SCRIPT_FILE"
grep -q 'brew install --cask "\$entry_name"' "$SCRIPT_FILE"
! grep -q 'brew bundle install --file=' "$SCRIPT_FILE"
grep -q 'fail "Homebrew is not installed\.' "$SCRIPT_FILE"
! grep -q 'raw.githubusercontent.com/Homebrew/install/HEAD/install.sh' "$SCRIPT_FILE"

echo "Brew install checks passed"
