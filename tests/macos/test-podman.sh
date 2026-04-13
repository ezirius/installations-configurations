#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/podman-configure"
test -f "$ROOT/config/podman/containers.conf"
test -f "$SCRIPT_FILE"
grep -q '^\[machine\]$' "$ROOT/config/podman/containers.conf"
grep -q '^cpus=4$' "$ROOT/config/podman/containers.conf"
grep -q '^memory=4096$' "$ROOT/config/podman/containers.conf"
grep -q '^disk_size=60$' "$ROOT/config/podman/containers.conf"
grep -q '^rootful=false$' "$ROOT/config/podman/containers.conf"
grep -q '^apply_machine_preferences() {$' "$SCRIPT_FILE"
grep -q '^machine_set_option_supported() {$' "$SCRIPT_FILE"
grep -q '^apply_machine_setting() {$' "$SCRIPT_FILE"
grep -q '^machine_is_running() {$' "$SCRIPT_FILE"
grep -q '^prepare_machine_for_update() {$' "$SCRIPT_FILE"
grep -q '^restore_machine_after_update() {$' "$SCRIPT_FILE"
grep -q '^  fail "podman is not installed; run scripts/macos/bootstrap or scripts/macos/brew-upgrade first"$' "$SCRIPT_FILE"
grep -q '^  podman machine init "\$MACHINE_NAME"$' "$SCRIPT_FILE"
grep -q '^  podman machine start "\$MACHINE_NAME"$' "$SCRIPT_FILE"
if ! command -v podman >/dev/null 2>&1; then
  echo "Podman checks passed (integration skipped: podman not installed)"
  exit 0
fi

podman machine list >/dev/null
podman info >/dev/null
echo "Podman checks passed"
