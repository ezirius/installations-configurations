#!/usr/bin/env bash
# Shared characterization test for the active macOS system workflow.
#
# This test covers:
# - layered macOS system config resolution under configs/<os>/system/
# - shared support for OS, host, and username slots
# - Dock auto-hide and Spaces ordering application through defaults
# - AC power sleep management through pmset and sudo
# - help output and argument handling
# - documentation headers for active system files
#
# It uses a temporary fake repo plus stubbed system commands so behavior can be
# verified without mutating the real machine.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT_SOURCE="$ROOT/scripts/macos/system/system-configure"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local file_path="$1"
  local expected="$2"
  local message="$3"

  if ! grep -Fq -- "$expected" "$file_path"; then
    printf 'Expected to find: %s\n' "$expected" >&2
    fail "$message"
  fi
}

assert_not_contains() {
  local file_path="$1"
  local unexpected="$2"
  local message="$3"

  if grep -Fq -- "$unexpected" "$file_path"; then
    printf 'Did not expect to find: %s\n' "$unexpected" >&2
    fail "$message"
  fi
}

assert_starts_with_comment() {
  local file_path="$1"
  local message="$2"
  local first_non_shebang

  first_non_shebang="$(grep -v '^#!' "$file_path" | grep -v '^[[:space:]]*$' | sed -n '1p')"
  case "$first_non_shebang" in
    \#*|\\#*) return 0 ;;
  esac
  fail "$message"
}

make_fake_repo() {
  local temp_dir="$1"

  mkdir -p \
    "$temp_dir/scripts/macos/system" \
    "$temp_dir/configs/shared/shared" \
    "$temp_dir/configs/shared/system" \
    "$temp_dir/configs/macos/system" \
    "$temp_dir/fake-bin" \
    "$temp_dir/libs/shared/shared"
  cp "$SCRIPT_SOURCE" "$temp_dir/scripts/macos/system/system-configure"
  cp "$ROOT/libs/shared/shared/common.sh" "$temp_dir/libs/shared/shared/common.sh"
  cp "$ROOT/configs/shared/shared/logging.conf" "$temp_dir/configs/shared/shared/logging.conf"
  chmod +x "$temp_dir/scripts/macos/system/system-configure"
}

write_command_stub() {
  local path="$1"
  local body="$2"

  printf '%s\n' "$body" > "$path"
  chmod +x "$path"
}

setup_common_stubs() {
  local temp_dir="$1"
  local fake_bin="$temp_dir/fake-bin"

  write_command_stub "$fake_bin/uname" '#!/usr/bin/env bash
printf "%s\n" "${TEST_UNAME:-Darwin}"'

  write_command_stub "$fake_bin/hostname" '#!/usr/bin/env bash
printf "%s\n" "${TEST_HOSTNAME:-maldoria.local}"'

  write_command_stub "$fake_bin/whoami" '#!/usr/bin/env bash
printf "%s\n" "${TEST_WHOAMI:-ezirius}"'

  write_command_stub "$fake_bin/date" '#!/usr/bin/env bash
case "$1" in
  +%Y%m%d)
    printf "%s\n" "${TEST_DATE_YYYYMMDD:-20260427}"
    ;;
  +%H%M%S)
    printf "%s\n" "${TEST_TIME_HHMMSS:-143015}"
    ;;
  *)
    exit 1
    ;;
esac'

  write_command_stub "$fake_bin/defaults" '#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${TEST_STATE_DIR:?}"
printf "%s\n" "$*" >> "$STATE_DIR/defaults.log"

case "$1" in
  read)
    case "$3" in
      autohide)
        if [[ "${TEST_DEFAULTS_AUTO_HIDE_MISSING:-0}" == "1" ]]; then
          exit 1
        fi
        printf "%s\n" "${TEST_DEFAULTS_AUTO_HIDE_CURRENT:-0}"
        ;;
      mru-spaces)
        if [[ "${TEST_DEFAULTS_MRU_SPACES_MISSING:-0}" == "1" ]]; then
          exit 1
        fi
        printf "%s\n" "${TEST_DEFAULTS_MRU_SPACES_CURRENT:-0}"
        ;;
      *) exit 1 ;;
    esac
    ;;
  write)
    :
    ;;
  *)
    exit 1
    ;;
esac'

  write_command_stub "$fake_bin/pmset" '#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${TEST_STATE_DIR:?}"
printf "%s\n" "$*" >> "$STATE_DIR/pmset.log"

case "$1" in
  -g)
    case "$2" in
      batt)
        if [[ -n "${TEST_PMSET_BATT_OUTPUT:-}" ]]; then
          printf "%s\n" "$TEST_PMSET_BATT_OUTPUT"
        elif [[ "${TEST_PMSET_PORTABLE:-0}" == "1" ]]; then
          printf "%s\n" "Now drawing from Battery Power" " -InternalBattery-0 (id=1234567) 100%; charged; 0:00 remaining present: true"
        else
          printf "%s\n" "No battery"
        fi
        ;;
      custom)
        printf "%s\n" "AC Power:" " sleep ${TEST_PMSET_CURRENT_SLEEP:-10}"
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  -c|-a)
    :
    ;;
  *)
    exit 1
    ;;
esac'

  write_command_stub "$fake_bin/sudo" '#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${TEST_STATE_DIR:?}"
printf "%s\n" "$*" >> "$STATE_DIR/sudo.log"

if [[ "$1" == "-v" ]]; then
  exit 0
fi

exec "$@"'

  write_command_stub "$fake_bin/killall" '#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${TEST_STATE_DIR:?}"
printf "%s\n" "$*" >> "$STATE_DIR/killall.log"'
}

run_in_fake_repo() {
  local temp_dir="$1"
  local output_file="$2"

  TEST_STATE_DIR="$temp_dir/state" \
  PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$temp_dir/scripts/macos/system/system-configure" > "$output_file" 2>&1
}

write_shared_shared_config() {
  local temp_dir="$1"

  cat > "$temp_dir/configs/shared/system/system-shared-shared.conf" <<'EOF'
# Shared system settings for all OS scopes, hosts, and usernames.
DOCK_AUTO_HIDE=true
DOCK_REORDER_SPACES_BY_RECENT_USE=false
AC_POWER_SYSTEM_SLEEP_MINUTES=0
SYSTEM_DOCK_DOMAIN="com.apple.dock"
SYSTEM_DOCK_AUTO_HIDE_KEY="autohide"
SYSTEM_DOCK_REORDER_SPACES_KEY="mru-spaces"
SYSTEM_DOCK_AUTO_HIDE_LOG_TOKEN="system-dock-autohide"
SYSTEM_DOCK_REORDER_SPACES_LOG_TOKEN="system-dock-mru-spaces"
SYSTEM_PMSET_AC_POWER_SECTION="AC Power"
SYSTEM_PMSET_SLEEP_LOG_TOKEN="system-pmset-sleep"
SYSTEM_PMSET_PORTABLE_SLEEP_SCOPE="-c"
SYSTEM_PMSET_NON_PORTABLE_SLEEP_SCOPE="-a"
EOF
}

write_shared_host_override() {
  local temp_dir="$1"
  local host_name="$2"
  local body="$3"

  cat > "$temp_dir/configs/shared/system/system-$host_name-shared.conf" <<EOF
# Shared system overrides for host '$host_name'.
$body
EOF
}

write_shared_user_override() {
  local temp_dir="$1"
  local user_name="$2"
  local body="$3"

  cat > "$temp_dir/configs/shared/system/system-shared-$user_name.conf" <<EOF
# Shared system overrides for user '$user_name'.
$body
EOF
}

write_shared_host_user_override() {
  local temp_dir="$1"
  local host_name="$2"
  local user_name="$3"
  local body="$4"

  cat > "$temp_dir/configs/shared/system/system-$host_name-$user_name.conf" <<EOF
# Shared system overrides for host '$host_name' and user '$user_name'.
$body
EOF
}

write_macos_host_user_override() {
  local temp_dir="$1"
  local host_name="$2"
  local user_name="$3"
  local body="$4"

  cat > "$temp_dir/configs/macos/system/system-$host_name-$user_name.conf" <<EOF
# macOS system overrides for host '$host_name' and user '$user_name'.
$body
EOF
}

test_help_output() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  if ! PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/system/system-configure" --help > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'system-configure should show help successfully'
  fi

  assert_contains "$output_file" 'Usage: system-configure' 'shows system help usage'
  assert_contains "$output_file" '[-h|--help]' 'documents both help flags'
  assert_contains "$output_file" 'Loads matching layered system config files in order.' 'documents layered config loading'
}

test_short_help_output() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  if ! PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/system/system-configure" -h > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'system-configure should show short help successfully'
  fi

  assert_contains "$output_file" 'Usage: system-configure' 'shows system short help usage'
  assert_contains "$output_file" '[-h|--help]' 'documents both help flags in short help'
  assert_contains "$output_file" 'Loads matching layered system config files in order.' 'documents layered config loading in short help'
}

test_rejects_positional_arguments() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  if PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/system/system-configure" unexpected > "$output_file" 2>&1; then
    fail 'system-configure should fail when given positional arguments'
  fi

  assert_contains "$output_file" 'ERROR: system-configure takes no arguments. Use --help for usage.' 'system-configure should use the aligned invalid-argument message'
}

test_requires_macos() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  if TEST_UNAME=Linux PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/macos/system/system-configure" > "$output_file" 2>&1; then
    fail 'system-configure should fail outside macOS'
  fi

  assert_contains "$output_file" 'ERROR: This script is for macOS only' 'system-configure should fail with a clear macOS-only message'
}

test_fails_when_no_matching_system_config_layers_exist() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'system-configure should fail when no matching layered config files exist'
  fi

  assert_contains "$output_file" 'ERROR: No matching system config files found for os=macos host=maldoria username=ezirius' 'system-configure should fail clearly when no layered config files match'
}

test_requires_system_config_values_from_final_layered_config() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  cat > "$temp_dir/configs/shared/system/system-shared-shared.conf" <<'EOF'
# Shared system settings for all OS scopes, hosts, and usernames.
DOCK_AUTO_HIDE=true
DOCK_REORDER_SPACES_BY_RECENT_USE=false
AC_POWER_SYSTEM_SLEEP_MINUTES=0
SYSTEM_DOCK_DOMAIN="com.apple.dock"
SYSTEM_DOCK_AUTO_HIDE_KEY="autohide"
SYSTEM_DOCK_REORDER_SPACES_KEY="mru-spaces"
SYSTEM_DOCK_REORDER_SPACES_LOG_TOKEN="system-dock-mru-spaces"
SYSTEM_PMSET_AC_POWER_SECTION="AC Power"
SYSTEM_PMSET_SLEEP_LOG_TOKEN="system-pmset-sleep"
SYSTEM_PMSET_PORTABLE_SLEEP_SCOPE="-c"
SYSTEM_PMSET_NON_PORTABLE_SLEEP_SCOPE="-a"
EOF

  if SYSTEM_DOCK_AUTO_HIDE_LOG_TOKEN='system-dock-autohide' run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'system-configure should fail when a required layered config value is missing even if exported in the environment'
  fi

  assert_contains "$output_file" 'ERROR: SYSTEM_DOCK_AUTO_HIDE_LOG_TOKEN is not set in the managed macOS system config' 'system-configure should require managed values to come from layered config files themselves'
}

test_rejects_invalid_sleep_minutes_before_applying_changes() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"
  write_shared_host_override "$temp_dir" 'maldoria' 'AC_POWER_SYSTEM_SLEEP_MINUTES=never'

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'system-configure should reject invalid sleep minutes before applying changes'
  fi

  assert_contains "$output_file" 'ERROR: Invalid AC_POWER_SYSTEM_SLEEP_MINUTES value: never' 'system-configure should fail clearly on invalid sleep minutes'
  assert_not_contains "$temp_dir/state/defaults.log" 'write com.apple.dock' 'invalid sleep config should fail before Dock writes'
  assert_not_contains "$temp_dir/state/sudo.log" '-v' 'invalid sleep config should fail before sudo validation'
  assert_not_contains "$temp_dir/state/pmset.log" ' sleep ' 'invalid sleep config should fail before pmset writes'
}

test_rejects_invalid_pmset_scope_before_applying_changes() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"
  write_shared_user_override "$temp_dir" 'ezirius' 'SYSTEM_PMSET_PORTABLE_SLEEP_SCOPE="portable"'

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'system-configure should reject invalid pmset scope before applying changes'
  fi

  assert_contains "$output_file" 'ERROR: Invalid SYSTEM_PMSET_PORTABLE_SLEEP_SCOPE value: portable' 'system-configure should fail clearly on invalid pmset scope'
  assert_not_contains "$temp_dir/state/defaults.log" 'write com.apple.dock' 'invalid pmset scope should fail before Dock writes'
  assert_not_contains "$temp_dir/state/sudo.log" '-v' 'invalid pmset scope should fail before sudo validation'
  assert_not_contains "$temp_dir/state/pmset.log" ' sleep ' 'invalid pmset scope should fail before pmset writes'
}

test_applies_shared_shared_system_config_on_portable_mac() {
  local temp_dir
  local output_file
  local log_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  log_file="$temp_dir/logs/macos/shared/installations-and-configurations-maldoria.csv"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"

  if ! TEST_DEFAULTS_AUTO_HIDE_CURRENT=0 TEST_DEFAULTS_MRU_SPACES_CURRENT=1 TEST_PMSET_CURRENT_SLEEP=10 TEST_PMSET_PORTABLE=1 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should apply shared shared system settings'
  fi

  assert_contains "$temp_dir/state/defaults.log" 'write com.apple.dock autohide -bool true' 'writes Dock auto-hide setting'
  assert_contains "$temp_dir/state/defaults.log" 'write com.apple.dock mru-spaces -bool false' 'writes Dock spaces setting'
  assert_contains "$temp_dir/state/killall.log" 'Dock' 'restarts Dock when Dock settings changed'
  assert_contains "$temp_dir/state/sudo.log" '-v' 'validates sudo before pmset change'
  assert_contains "$temp_dir/state/pmset.log" '-c sleep 0' 'uses portable pmset scope on battery-capable Macs'
  assert_contains "$log_file" 'date,time,host,action,application,version' 'system log file should contain csv header'
  assert_contains "$log_file" '20260427,143015,maldoria,Updated,system-dock-autohide,' 'logs Dock auto-hide change'
  assert_contains "$log_file" '20260427,143015,maldoria,Updated,system-dock-mru-spaces,' 'logs Dock spaces change'
  assert_contains "$log_file" '20260427,143015,maldoria,Updated,system-pmset-sleep,' 'logs pmset sleep change'
}

test_prefers_x_shared_over_shared_x_when_both_match() {
  local temp_dir
  local output_file
  local log_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  log_file="$temp_dir/logs/macos/shared/installations-and-configurations-maldoria.csv"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"
  write_shared_user_override "$temp_dir" 'ezirius' 'DOCK_REORDER_SPACES_BY_RECENT_USE=true'
  write_shared_host_override "$temp_dir" 'maldoria' 'DOCK_REORDER_SPACES_BY_RECENT_USE=false'

  if ! TEST_DEFAULTS_AUTO_HIDE_CURRENT=1 TEST_DEFAULTS_MRU_SPACES_CURRENT=1 TEST_PMSET_CURRENT_SLEEP=0 TEST_PMSET_PORTABLE=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should prefer x.shared over shared.x when both match'
  fi

  assert_contains "$temp_dir/state/defaults.log" 'write com.apple.dock mru-spaces -bool false' 'host-shared override should win over user-shared override'
  assert_contains "$log_file" '20260427,143015,maldoria,Updated,system-dock-mru-spaces,' 'logs the host-shared override application'
}

test_prefers_x_x_over_all_earlier_layers() {
  local temp_dir
  local output_file
  local log_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  log_file="$temp_dir/logs/macos/shared/installations-and-configurations-maldoria.csv"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"
  write_shared_user_override "$temp_dir" 'ezirius' 'DOCK_AUTO_HIDE=false'
  write_shared_host_override "$temp_dir" 'maldoria' 'DOCK_AUTO_HIDE=true'
  write_shared_host_user_override "$temp_dir" 'maldoria' 'ezirius' 'DOCK_AUTO_HIDE=false'

  if ! TEST_DEFAULTS_AUTO_HIDE_CURRENT=1 TEST_DEFAULTS_MRU_SPACES_CURRENT=0 TEST_PMSET_CURRENT_SLEEP=0 TEST_PMSET_PORTABLE=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should prefer host-user override over all earlier layers'
  fi

  assert_contains "$temp_dir/state/defaults.log" 'write com.apple.dock autohide -bool false' 'host-user override should win over earlier shared layers'
  assert_contains "$log_file" '20260427,143015,maldoria,Updated,system-dock-autohide,' 'logs the host-user override application'
}

test_applies_non_portable_sleep_change_with_a_scope() {
  local temp_dir
  local output_file
  local log_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  log_file="$temp_dir/logs/macos/shared/installations-and-configurations-maldoria.csv"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"

  if ! TEST_DEFAULTS_AUTO_HIDE_CURRENT=1 TEST_DEFAULTS_MRU_SPACES_CURRENT=0 TEST_PMSET_CURRENT_SLEEP=10 TEST_PMSET_PORTABLE=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should apply a changed non-portable sleep setting'
  fi

  assert_contains "$temp_dir/state/sudo.log" '-v' 'validates sudo before non-portable pmset change'
  assert_contains "$temp_dir/state/pmset.log" '-a sleep 0' 'uses non-portable pmset scope on desktop Macs'
  assert_contains "$log_file" '20260427,143015,maldoria,Updated,system-pmset-sleep,' 'logs changed non-portable pmset setting'
}

test_partial_override_files_inherit_required_values_from_baseline() {
  local temp_dir
  local output_file
  local log_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  log_file="$temp_dir/logs/macos/shared/installations-and-configurations-maldoria.csv"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"
  write_shared_host_override "$temp_dir" 'maldoria' 'DOCK_REORDER_SPACES_BY_RECENT_USE=true'

  if ! TEST_DEFAULTS_AUTO_HIDE_CURRENT=1 TEST_DEFAULTS_MRU_SPACES_CURRENT=0 TEST_PMSET_CURRENT_SLEEP=0 TEST_PMSET_PORTABLE=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should allow partial override files when the baseline provides required keys'
  fi

  assert_contains "$temp_dir/state/defaults.log" 'write com.apple.dock mru-spaces -bool true' 'partial host override should inherit required keys from baseline and apply its override'
  assert_contains "$log_file" '20260427,143015,maldoria,Updated,system-dock-mru-spaces,' 'logs the inherited partial override change'
}

test_skips_dock_restart_when_dock_settings_are_already_correct() {
  local temp_dir
  local output_file
  local log_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  log_file="$temp_dir/logs/macos/shared/installations-and-configurations-maldoria.csv"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"

  if ! TEST_DEFAULTS_AUTO_HIDE_CURRENT=1 TEST_DEFAULTS_MRU_SPACES_CURRENT=0 TEST_PMSET_CURRENT_SLEEP=0 TEST_PMSET_PORTABLE=1 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should succeed when Dock and pmset settings are already correct'
  fi

  assert_not_contains "$temp_dir/state/defaults.log" 'write com.apple.dock' 'does not rewrite unchanged Dock settings'
  assert_not_contains "$temp_dir/state/killall.log" 'Dock' 'does not restart Dock when no Dock settings changed'
  assert_not_contains "$temp_dir/state/sudo.log" '-v' 'does not request sudo when pmset is already correct'
  if [[ -f "$log_file" ]]; then
    assert_not_contains "$log_file" 'system-dock-' 'does not log unchanged Dock settings'
    assert_not_contains "$log_file" 'system-pmset-sleep' 'does not log unchanged pmset setting'
  fi
}

test_uses_portable_scope_when_pmset_reports_battery_power_without_internalbattery_token() {
  local temp_dir
  local output_file
  local log_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  log_file="$temp_dir/logs/macos/shared/installations-and-configurations-maldoria.csv"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"

  if ! TEST_DEFAULTS_AUTO_HIDE_CURRENT=1 TEST_DEFAULTS_MRU_SPACES_CURRENT=0 TEST_PMSET_CURRENT_SLEEP=10 TEST_PMSET_BATT_OUTPUT='Now drawing from Battery Power' run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should use the portable pmset scope when battery power is reported'
  fi

  assert_contains "$temp_dir/state/sudo.log" '-v' 'validates sudo before portable pmset change'
  assert_contains "$temp_dir/state/pmset.log" '-c sleep 0' 'uses portable pmset scope when battery power is reported without the InternalBattery token'
  assert_contains "$log_file" '20260427,143015,maldoria,Updated,system-pmset-sleep,' 'logs the portable sleep change'
}

test_documentation_headers() {
  assert_starts_with_comment "$ROOT/configs/shared/system/system-shared-shared.conf" 'shared shared system config should start with a header comment'
  assert_starts_with_comment "$ROOT/configs/shared/system/system-maldoria-shared.conf" 'shared host system config should start with a header comment'
  assert_starts_with_comment "$ROOT/configs/shared/system/system-maravyn-shared.conf" 'second shared host system config should start with a header comment'
  assert_starts_with_comment "$ROOT/scripts/macos/system/system-configure" 'system script should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/tests/shared/system/test-system-configure.sh" 'system test should start with a header comment after shebang'
}

test_help_output
test_short_help_output
test_rejects_positional_arguments
test_requires_macos
test_fails_when_no_matching_system_config_layers_exist
test_requires_system_config_values_from_final_layered_config
test_rejects_invalid_sleep_minutes_before_applying_changes
test_rejects_invalid_pmset_scope_before_applying_changes
test_applies_shared_shared_system_config_on_portable_mac
test_prefers_x_shared_over_shared_x_when_both_match
test_prefers_x_x_over_all_earlier_layers
test_applies_non_portable_sleep_change_with_a_scope
test_partial_override_files_inherit_required_values_from_baseline
test_skips_dock_restart_when_dock_settings_are_already_correct
test_uses_portable_scope_when_pmset_reports_battery_power_without_internalbattery_token
test_documentation_headers

printf 'PASS: tests/shared/system/test-system-configure.sh\n'
