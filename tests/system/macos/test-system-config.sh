#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/system/macos/system-configure"
CONFIG_FILE="$ROOT/config/system/macos/system-settings-shared.conf"

test -f "$SCRIPT_FILE"
test -f "$CONFIG_FILE"
grep -q '^DOCK_AUTO_HIDE=true$' "$CONFIG_FILE"
grep -q '^DOCK_REORDER_SPACES_BY_RECENT_USE=false$' "$CONFIG_FILE"
grep -q '^AC_POWER_SYSTEM_SLEEP_MINUTES=0$' "$CONFIG_FILE"
grep -q '^SYSTEM_DOCK_DOMAIN="com.apple.dock"$' "$CONFIG_FILE"
grep -q '^SYSTEM_DOCK_AUTO_HIDE_KEY="autohide"$' "$CONFIG_FILE"
grep -q '^SYSTEM_DOCK_REORDER_SPACES_KEY="mru-spaces"$' "$CONFIG_FILE"
grep -q '^SYSTEM_PMSET_AC_POWER_SECTION="AC Power"$' "$CONFIG_FILE"
grep -q '^SYSTEM_PMSET_PORTABLE_SLEEP_SCOPE="-c"$' "$CONFIG_FILE"
grep -q '^SYSTEM_PMSET_NON_PORTABLE_SLEEP_SCOPE="-a"$' "$CONFIG_FILE"
if grep -q '^SYSTEM_DOCK_SETTINGS=($' "$CONFIG_FILE"; then
  printf 'assertion failed: system config should not keep tuple-style dock metadata\n' >&2
  exit 1
fi
if grep -q '^SYSTEM_DOCK_AUTO_HIDE_LABEL=' "$CONFIG_FILE"; then
  printf 'assertion failed: system config should not keep unused dock auto-hide labels\n' >&2
  exit 1
fi
if grep -q '^SYSTEM_DOCK_REORDER_SPACES_LABEL=' "$CONFIG_FILE"; then
  printf 'assertion failed: system config should not keep unused dock reorder labels\n' >&2
  exit 1
fi
if grep -q '^system_setting_value() {$' "$SCRIPT_FILE"; then
  printf 'assertion failed: system-configure should not keep tuple decoding helpers\n' >&2
  exit 1
fi
if grep -q 'SYSTEM_DOCK_AUTO_HIDE_LABEL' "$SCRIPT_FILE"; then
  printf 'assertion failed: system-configure should not reference dock auto-hide labels\n' >&2
  exit 1
fi
if grep -q 'SYSTEM_DOCK_REORDER_SPACES_LABEL' "$SCRIPT_FILE"; then
  printf 'assertion failed: system-configure should not reference dock reorder labels\n' >&2
  exit 1
fi
grep -q '^  sudo pmset "\$scope_flag" sleep "\$desired_value"$' "$SCRIPT_FILE"

echo "System config checks passed"
