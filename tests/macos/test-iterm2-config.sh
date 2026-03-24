#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG_FILE="$ROOT/config/iterm2/defaults.conf"
SCRIPT_FILE="$ROOT/scripts/macos/iterm2-configure"
test -f "$CONFIG_FILE"
test -f "$SCRIPT_FILE"
grep -q '^bool|AllowClipboardAccess|true$' "$CONFIG_FILE"
grep -q '^ITERM_DOMAIN="com.googlecode.iterm2"$' "$SCRIPT_FILE"
grep -q '^  defaults write "\$ITERM_DOMAIN" "\$key" -bool "\$desired_value"$' "$SCRIPT_FILE"
grep -q '^  \[\[ "\$verified_value" == "\$desired_value" \]\] || fail "Failed to verify iTerm2 setting \$key"$' "$SCRIPT_FILE"
echo "iTerm2 config checks passed"
