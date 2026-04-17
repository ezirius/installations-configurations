#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/caddy/macos/caddy-trust"
CONFIG_FILE="$ROOT/config/caddy/macos/caddy-settings-shared.conf"
test -f "$CONFIG_FILE"
test -f "$SCRIPT_FILE"
grep -q '^find_trusted_keychain() {$' "$SCRIPT_FILE"
grep -q 'source_layered_scoped_config "config/caddy" "macos" "caddy-settings" "conf"' "$SCRIPT_FILE"
grep -q '^CADDY_TRUST_CERT_NAME=' "$CONFIG_FILE"
grep -q '^require_command security$' "$SCRIPT_FILE"
grep -q '^caddy trust --config "\$TARGET_CONFIG" --adapter caddyfile >/dev/null$' "$SCRIPT_FILE"
echo "Caddy trust checks passed"
