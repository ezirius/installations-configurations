#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/brew-bootstrap"
CONFIG_FILE="$ROOT/config/brew/shared-macos.conf"
test -f "$SCRIPT_FILE"
test -f "$CONFIG_FILE"
grep -q '^source "\$SCRIPT_DIR/../../lib/shell/common.sh"$' "$SCRIPT_FILE"
grep -q '^require_macos$' "$SCRIPT_FILE"
grep -q '^BREW_BOOTSTRAP_STEPS=($' "$CONFIG_FILE"
grep -q '^for step in "\${BREW_BOOTSTRAP_STEPS\[@\]}"; do$' "$SCRIPT_FILE"
grep -q '^"\$SCRIPT_DIR/brew-service" "\$BREW_BOOTSTRAP_SERVICE_ACTION"$' "$SCRIPT_FILE"
echo "Brew bootstrap checks passed"
