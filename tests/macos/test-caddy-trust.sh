#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/caddy-trust"
test -f "$SCRIPT_FILE"
grep -q '^find_trusted_keychain() {$' "$SCRIPT_FILE"
grep -q '^require_command security$' "$SCRIPT_FILE"
grep -q '^initialize_change_log "scripts/macos/caddy-trust"$' "$SCRIPT_FILE"
grep -q '^caddy trust --config "\$TARGET_CONFIG" --adapter caddyfile >/dev/null$' "$SCRIPT_FILE"
grep -q '^log_change "Configuration" "Caddy local CA" "Trusted" "\$TRUSTED_KEYCHAIN" "Trusted the managed Caddy local CA for local HTTPS"$' "$SCRIPT_FILE"
echo "Caddy trust checks passed"
