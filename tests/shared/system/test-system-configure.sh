#!/usr/bin/env bash
# Shared characterization test for the active macOS system workflow.
#
# This test covers:
# - macOS-only host-fallback config resolution under configs/<os>/system/
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
    "$temp_dir/configs/macos/system" \
    "$temp_dir/fake-bin" \
    "$temp_dir/libs/shared/shared"
  cp "$SCRIPT_SOURCE" "$temp_dir/scripts/macos/system/system-configure"
  cp "$ROOT/libs/shared/shared/common.sh" "$temp_dir/libs/shared/shared/common.sh"
  cp "$ROOT/configs/shared/shared/logging-shared.conf" "$temp_dir/configs/shared/shared/logging-shared.conf"
  chmod +x "$temp_dir/scripts/macos/system/system-configure"
}

# Write a small executable stub used to isolate external command behavior.
write_command_stub() {
  local path="$1"
  local body="$2"

  printf '%s\n' "$body" > "$path"
  chmod +x "$path"
}

# Provide deterministic uname, hostname, whoami, defaults, pmset, sudo, and
# killall behavior for the isolated fake repo.
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
        if [[ "${TEST_PMSET_PORTABLE:-0}" == "1" ]]; then
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

# Run the active system script inside the fake repo with stubbed commands.
run_in_fake_repo() {
  local temp_dir="$1"
  local output_file="$2"

  TEST_STATE_DIR="$temp_dir/state" \
  PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$temp_dir/scripts/macos/system/system-configure" > "$output_file" 2>&1
}

# Write the shared macOS system config used by the isolated tests.
write_shared_config() {
  local temp_dir="$1"

  cat > "$temp_dir/configs/macos/system/system-settings-shared.conf" <<'EOF'
# Shared macOS system settings.
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
  assert_contains "$output_file" 'Requires sudo for the managed pmset change.' 'documents sudo requirement'
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

test_requires_system_config_file() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'system-configure should fail when the managed system config file is missing'
  fi

  assert_contains "$output_file" 'ERROR: Managed macOS system config not found:' 'system-configure should fail clearly when the managed config file is missing'
}

test_requires_system_config_values_from_config_file() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  cat > "$temp_dir/configs/macos/system/system-settings-shared.conf" <<'EOF'
# Shared macOS system settings.
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
    fail 'system-configure should fail when a required config value is missing from the config file even if exported in the environment'
  fi

  assert_contains "$output_file" 'ERROR: SYSTEM_DOCK_AUTO_HIDE_LOG_TOKEN is not set in the managed macOS system config' 'system-configure should require managed values to come from the config file itself'
}

# Verify that the shared config is applied on a portable Mac when values differ.
test_applies_shared_system_config_on_portable_mac() {
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
  write_shared_config "$temp_dir"

  if ! TEST_DEFAULTS_AUTO_HIDE_CURRENT=0 TEST_DEFAULTS_MRU_SPACES_CURRENT=1 TEST_PMSET_CURRENT_SLEEP=10 TEST_PMSET_PORTABLE=1 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should apply shared macOS settings'
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

# Verify host-specific override selection and no-op pmset behavior.
test_prefers_host_specific_override_and_skips_unchanged_sleep() {
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
  write_shared_config "$temp_dir"

  cat > "$temp_dir/configs/macos/system/system-settings-maldoria.conf" <<'EOF'
# Host-specific macOS system settings.
DOCK_AUTO_HIDE=false
DOCK_REORDER_SPACES_BY_RECENT_USE=true
AC_POWER_SYSTEM_SLEEP_MINUTES=10
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

  if ! TEST_DEFAULTS_AUTO_HIDE_CURRENT=0 TEST_DEFAULTS_MRU_SPACES_CURRENT=0 TEST_PMSET_CURRENT_SLEEP=10 TEST_PMSET_PORTABLE=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should prefer host-specific config'
  fi

  assert_not_contains "$temp_dir/state/defaults.log" 'write com.apple.dock autohide -bool true' 'host-specific override should prevent shared auto-hide write'
  assert_contains "$temp_dir/state/defaults.log" 'write com.apple.dock mru-spaces -bool true' 'host-specific override should apply host spaces setting'
  assert_contains "$temp_dir/state/killall.log" 'Dock' 'host-specific Dock change should restart Dock'
  assert_not_contains "$temp_dir/state/sudo.log" '-v' 'unchanged pmset setting should not require sudo'
  assert_not_contains "$temp_dir/state/pmset.log" '-a sleep 10' 'unchanged non-portable sleep setting should not be reapplied'
  assert_contains "$log_file" '20260427,143015,maldoria,Updated,system-dock-mru-spaces,' 'logs only changed host-specific Dock setting'
  assert_not_contains "$log_file" 'system-dock-autohide' 'does not log unchanged auto-hide setting'
  assert_not_contains "$log_file" 'system-pmset-sleep' 'does not log unchanged pmset setting'
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
  write_shared_config "$temp_dir"

  if ! TEST_DEFAULTS_AUTO_HIDE_CURRENT=1 TEST_DEFAULTS_MRU_SPACES_CURRENT=0 TEST_PMSET_CURRENT_SLEEP=10 TEST_PMSET_PORTABLE=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should apply a changed non-portable sleep setting'
  fi

  assert_contains "$temp_dir/state/sudo.log" '-v' 'validates sudo before non-portable pmset change'
  assert_contains "$temp_dir/state/pmset.log" '-a sleep 0' 'uses non-portable pmset scope on desktop Macs'
  assert_contains "$log_file" '20260427,143015,maldoria,Updated,system-pmset-sleep,' 'logs changed non-portable pmset setting'
}

test_enforces_false_dock_value_when_key_is_unset() {
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
  write_shared_config "$temp_dir"

  if ! TEST_DEFAULTS_AUTO_HIDE_CURRENT=1 TEST_DEFAULTS_MRU_SPACES_MISSING=1 TEST_PMSET_CURRENT_SLEEP=0 TEST_PMSET_PORTABLE=1 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should write managed false values when defaults keys are unset'
  fi

  assert_contains "$temp_dir/state/defaults.log" 'write com.apple.dock mru-spaces -bool false' 'writes missing Dock key for managed false value'
  assert_contains "$temp_dir/state/killall.log" 'Dock' 'restarts Dock when an unset key is enforced'
  assert_contains "$log_file" '20260427,143015,maldoria,Updated,system-dock-mru-spaces,' 'logs enforced false Dock value when key was unset'
  assert_not_contains "$temp_dir/state/sudo.log" '-v' 'unchanged pmset value should still skip sudo'
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
  write_shared_config "$temp_dir"

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

# Verify top-level documentation headers for the active system files.
test_documentation_headers() {
  assert_starts_with_comment "$ROOT/configs/macos/system/system-settings-shared.conf" 'system config should start with a header comment'
  assert_starts_with_comment "$ROOT/scripts/macos/system/system-configure" 'system script should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/tests/shared/system/test-system-configure.sh" 'system test should start with a header comment after shebang'
}

test_help_output
test_rejects_positional_arguments
test_requires_macos
test_requires_system_config_file
test_requires_system_config_values_from_config_file
test_applies_shared_system_config_on_portable_mac
test_prefers_host_specific_override_and_skips_unchanged_sleep
test_applies_non_portable_sleep_change_with_a_scope
test_enforces_false_dock_value_when_key_is_unset
test_skips_dock_restart_when_dock_settings_are_already_correct
test_documentation_headers

printf 'PASS: tests/shared/system/test-system-configure.sh\n'
