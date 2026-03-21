#!/usr/bin/env bash
set -euo pipefail
command -v podman >/dev/null
podman machine list >/dev/null
podman info >/dev/null
echo "Podman checks passed"
