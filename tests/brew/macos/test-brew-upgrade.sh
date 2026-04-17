#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/brew/macos/brew-upgrade"
test -f "$SCRIPT_FILE"
! grep -q 'brew bundle install --file=' "$SCRIPT_FILE"
echo "Brew upgrade checks passed"
