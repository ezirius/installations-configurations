#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/system-configure"
CONFIG_FILE="$ROOT/config/system/shared-macos.conf"

test -f "$SCRIPT_FILE"
test -f "$CONFIG_FILE"
grep -q '^DOCK_AUTOHIDE=true$' "$CONFIG_FILE"
grep -q '^DOCK_MRU_SPACES=false$' "$CONFIG_FILE"
grep -q '^PMSET_AC_SLEEP=0$' "$CONFIG_FILE"
grep -q '^load_system_config() {$' "$SCRIPT_FILE"
grep -q '^set_dock_bool() {$' "$SCRIPT_FILE"
grep -q '^apply_pmset_sleep() {$' "$SCRIPT_FILE"
grep -q '^  sudo pmset "\$scope_flag" sleep "\$desired_value"$' "$SCRIPT_FILE"

echo "System config checks passed"
