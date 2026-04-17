#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CONFIG_FILE="$ROOT/config/caddy/macos/caddy-runtime-shared.Caddyfile"
METADATA_FILE="$ROOT/config/caddy/macos/caddy-settings-shared.conf"
SCRIPT_FILE="$ROOT/scripts/caddy/macos/caddy-configure"
test -f "$CONFIG_FILE"
test -f "$METADATA_FILE"
test -f "$SCRIPT_FILE"
grep -q '^https://127.0.0.1:8123 {$' "$CONFIG_FILE"
grep -q '^    reverse_proxy https://hovaryn.mioverso.com:8123$' "$CONFIG_FILE"
grep -q '^CADDY_RUNTIME_RELATIVE_PATH=' "$METADATA_FILE"
! grep -q '^CADDY_LISTENER_PORT=' "$METADATA_FILE"
grep -q 'CADDY_RUNTIME_RELATIVE_PATH' "$SCRIPT_FILE"
grep -q 'source_layered_scoped_config "config/caddy" "macos" "caddy-settings" "conf"' "$SCRIPT_FILE"
grep -q 'shared_scoped_config_path "config/caddy" "macos" "caddy-runtime" "Caddyfile"' "$SCRIPT_FILE"
grep -q 'host_scoped_config_path "config/caddy" "macos" "caddy-runtime" "Caddyfile"' "$SCRIPT_FILE"
if grep -Eq '^  \[\[ -f "\$shared_runtime" \]\] && RUNTIME_SOURCES\+=' "$SCRIPT_FILE"; then
  printf 'assertion failed: caddy-configure should not probe optional shared runtime files with bare [[ -f ]] && under set -e\n' >&2
  exit 1
fi
if grep -Eq '^  \[\[ -f "\$host_runtime" \]\] && RUNTIME_SOURCES\+=' "$SCRIPT_FILE"; then
  printf 'assertion failed: caddy-configure should not probe optional host runtime files with bare [[ -f ]] && under set -e\n' >&2
  exit 1
fi
grep -q 'caddy validate --config' "$SCRIPT_FILE"
echo "Caddy config checks passed"
