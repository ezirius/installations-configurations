#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/podman-machine-install"
test -f "$ROOT/config/containers/containers.conf"
test -f "$SCRIPT_FILE"
grep -q '^\[machine\]$' "$ROOT/config/containers/containers.conf"
grep -q '^cpus=4$' "$ROOT/config/containers/containers.conf"
grep -q '^memory=4096$' "$ROOT/config/containers/containers.conf"
grep -q '^disk_size=60$' "$ROOT/config/containers/containers.conf"
grep -q '^rootful=false$' "$ROOT/config/containers/containers.conf"
grep -q '^apply_machine_preferences() {$' "$SCRIPT_FILE"
grep -q '^  podman machine init "\$MACHINE_NAME"$' "$SCRIPT_FILE"
grep -q '^  podman machine start "\$MACHINE_NAME"$' "$SCRIPT_FILE"
command -v podman >/dev/null
podman machine list >/dev/null
podman info >/dev/null
echo "Podman checks passed"
