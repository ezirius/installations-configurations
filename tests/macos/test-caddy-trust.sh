#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/caddy-trust"
CONFIG_FILE="$ROOT/config/caddy/shared-macos.conf"
test -f "$CONFIG_FILE"
test -f "$SCRIPT_FILE"
grep -q '^find_trusted_keychain() {$' "$SCRIPT_FILE"
grep -q '^CADDY_TRUST_CERT_NAME=' "$CONFIG_FILE"
grep -q '^require_command security$' "$SCRIPT_FILE"
grep -q '^caddy trust --config "\$TARGET_CONFIG" --adapter caddyfile >/dev/null$' "$SCRIPT_FILE"
echo "Caddy trust checks passed"
