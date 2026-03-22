#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
test -f "$ROOT/config/containers/containers.conf"
grep -q '^\[machine\]$' "$ROOT/config/containers/containers.conf"
grep -q '^cpus=4$' "$ROOT/config/containers/containers.conf"
grep -q '^memory=4096$' "$ROOT/config/containers/containers.conf"
grep -q '^disk_size=60$' "$ROOT/config/containers/containers.conf"
grep -q '^rootful=false$' "$ROOT/config/containers/containers.conf"
command -v podman >/dev/null
podman machine list >/dev/null
podman info >/dev/null
echo "Podman checks passed"
