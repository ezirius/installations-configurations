#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/brew-service"
CONFIG_FILE="$ROOT/config/brew/shared-macos.conf"

test -f "$SCRIPT_FILE"
test -f "$CONFIG_FILE"
grep -q '^require_macos$' "$SCRIPT_FILE"
grep -q '^ACTION="\$1"$' "$SCRIPT_FILE"
grep -q '^  start\|stop\|restart\|reload\|status' "$SCRIPT_FILE"
grep -q '^BREW_MANAGED_SERVICE_SCRIPTS=($' "$CONFIG_FILE"
grep -q 'BREW_MANAGED_SERVICE_SCRIPTS' "$SCRIPT_FILE"

echo "Brew service checks passed"
