#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG_FILE="$ROOT/config/git/maldoria.conf"
SCRIPT_FILE="$ROOT/scripts/macos/git-configure"

test -f "$CONFIG_FILE"
test -f "$SCRIPT_FILE"
grep -q '^sign|maldoria-github-ezirius-sign|ssh-ed25519 ' "$CONFIG_FILE"
grep -q '^repo|installations-configurations|maldoria-github-ezirius-installations-configurations|ssh-ed25519 ' "$CONFIG_FILE"
grep -q '^repo|nix-configurations|maldoria-github-ezirius-nix-configurations|ssh-ed25519 ' "$CONFIG_FILE"
grep -q 'change_name="Created"' "$SCRIPT_FILE"
grep -q 'change_name="Updated"' "$SCRIPT_FILE"
echo "Git host config checks passed"
