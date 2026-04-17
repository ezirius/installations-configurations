#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/brew/macos/brew-configure"
CONFIG_FILE="$ROOT/config/brew/macos/brew-settings-shared.conf"

test -f "$SCRIPT_FILE"
test -f "$CONFIG_FILE"
grep -q '^require_macos$' "$SCRIPT_FILE"
grep -q '^BREW_CONFIGURE_STEPS=($' "$CONFIG_FILE"
grep -q '^  "caddy-configure"$' "$CONFIG_FILE"
grep -q '^  "caddy-trust"$' "$CONFIG_FILE"
grep -q '^  "podman-configure"$' "$CONFIG_FILE"
grep -q '^  "system-configure"$' "$CONFIG_FILE"
grep -q 'resolve_brew_workflow_script_path' "$SCRIPT_FILE"
grep -q 'source_layered_scoped_config "config/brew" "macos" "brew-settings" "conf"' "$SCRIPT_FILE"

echo "Brew configure checks passed"
