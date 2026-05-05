#!/usr/bin/env bash
# Shared characterization test for the active macOS system workflow.
#
# This test covers:
# - layered macOS system config resolution under configs/<os>/system/
# - shared support for OS, host, and username slots
# - Dock auto-hide and Spaces ordering application through defaults
# - AC power sleep management through pmset and sudo
# - hardened SSH server enablement, config, and key deployment
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
    "$temp_dir/keys/macos/ssh" \
    "$temp_dir/fake-bin" \
    "$temp_dir/libs/shared/shared"
  cp "$SCRIPT_SOURCE" "$temp_dir/scripts/macos/system/system-configure"
  cp "$ROOT/libs/shared/shared/common.sh" "$temp_dir/libs/shared/shared/common.sh"
  cp "$ROOT/configs/shared/shared/logging.conf" "$temp_dir/configs/shared/shared/logging.conf"
  chmod +x "$temp_dir/scripts/macos/system/system-configure"
  write_system_support_config "$temp_dir"
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
    if [[ "$2" == "-g" ]]; then
      case "$3" in
        AppleICUForce24HourTime)
          if [[ "${TEST_DEFAULTS_24_HOUR_MISSING:-0}" == "1" ]]; then
            exit 1
          fi
          printf "%s\n" "${TEST_DEFAULTS_24_HOUR_CURRENT:-0}"
          ;;
        AppleICUForce12HourTime)
          if [[ "${TEST_DEFAULTS_12_HOUR_MISSING:-0}" == "1" ]]; then
            exit 1
          fi
          printf "%s\n" "${TEST_DEFAULTS_12_HOUR_CURRENT:-1}"
          ;;
        *) exit 1 ;;
      esac
    elif [[ "$2" == "/Library/Preferences/com.apple.timezone.auto" && "$3" == "Active" ]]; then
      if [[ "${TEST_TIME_ZONE_AUTO_MISSING:-0}" == "1" ]]; then
        exit 1
      fi
      printf "%s\n" "${TEST_TIME_ZONE_AUTO_CURRENT:-1}"
    else
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
    fi
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

  write_command_stub "$fake_bin/systemsetup" '#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${TEST_STATE_DIR:?}"
printf "%s\n" "$*" >> "$STATE_DIR/systemsetup.log"

case "$1" in
  -gettimezone)
    printf "Time Zone: %s\n" "${TEST_TIME_ZONE_CURRENT:-UTC}"
    ;;
  -listtimezones)
    printf "%s\n" "UTC" " Africa/Johannesburg" "America/New_York"
    ;;
  -settimezone)
    :
    ;;
  -getremotelogin)
    printf "Remote Login: %s\n" "${TEST_REMOTE_LOGIN_CURRENT:-Off}"
    ;;
  -setremotelogin)
    :
    ;;
  *)
    exit 1
    ;;
esac'

  write_command_stub "$fake_bin/sshd" '#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${TEST_STATE_DIR:?}"
printf "%s\n" "$*" >> "$STATE_DIR/sshd.log"

if [[ "${TEST_SSHD_VALIDATE_FAIL:-0}" == "1" ]]; then
  printf "%s\n" "sshd: configuration invalid" >&2
  exit 1
fi'

  write_command_stub "$fake_bin/launchctl" '#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${TEST_STATE_DIR:?}"
printf "%s\n" "$*" >> "$STATE_DIR/launchctl.log"'

  write_command_stub "$fake_bin/dscl" '#!/usr/bin/env bash
set -euo pipefail

user_record="$3"
if [[ "$1" != "." || "$2" != "-read" || "$4" != "NFSHomeDirectory" ]]; then
  exit 1
fi

user_name="${user_record##*/}"
printf "NFSHomeDirectory: %s/%s\n" "${TEST_HOME_ROOT:?}" "$user_name"'

  write_command_stub "$fake_bin/ssh-keygen" '#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${TEST_STATE_DIR:?}"
printf "%s\n" "$*" >> "$STATE_DIR/ssh-keygen.log"

if [[ "$1" != "-A" ]]; then
  exit 1
fi

if [[ "${TEST_SSH_KEYGEN_FAIL:-0}" == "1" ]]; then
  printf "%s\n" "ssh-keygen: failed to generate host keys" >&2
  exit 1
fi

if [[ "${TEST_SSH_KEYGEN_CREATE_ED25519:-1}" == "1" ]]; then
  key_path="${TEST_HOST_KEY_DIR:?}/ssh_host_ed25519_key"
  mkdir -p "$(dirname "$key_path")"
  printf "%s\n" "host-private-key" > "$key_path"
  printf "%s\n" "host-public-key" > "$key_path.pub"
fi'

  write_command_stub "$fake_bin/killall" '#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${TEST_STATE_DIR:?}"
printf "%s\n" "$*" >> "$STATE_DIR/killall.log"'
}

run_in_fake_repo() {
  local temp_dir="$1"
  local output_file="$2"

  TEST_STATE_DIR="$temp_dir/state" \
  TEST_HOME_ROOT="$temp_dir/home" \
  TEST_HOST_KEY_DIR="$temp_dir/state/etc/ssh" \
  PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$temp_dir/scripts/macos/system/system-configure" > "$output_file" 2>&1
}

write_shared_shared_config() {
  local temp_dir="$1"

  cat > "$temp_dir/configs/shared/system/system-shared-shared.conf" <<EOF
# Shared system settings for all OS scopes, hosts, and usernames.
DOCK_AUTO_HIDE=true
DOCK_REORDER_SPACES_BY_RECENT_USE=false
AC_POWER_SYSTEM_SLEEP_MINUTES=0
EOF
}

write_system_support_config() {
  local temp_dir="$1"

  cat > "$temp_dir/configs/shared/system/system-configure.conf" <<EOF
# Shared runtime support config for scripts/macos/system/system-configure.
SYSTEM_DOCK_DOMAIN="com.apple.dock"
SYSTEM_DOCK_AUTO_HIDE_KEY="autohide"
SYSTEM_DOCK_REORDER_SPACES_KEY="mru-spaces"
SYSTEM_DOCK_AUTO_HIDE_LOG_TOKEN="system-dock-autohide"
SYSTEM_DOCK_REORDER_SPACES_LOG_TOKEN="system-dock-mru-spaces"
SYSTEM_PMSET_AC_POWER_SECTION="AC Power"
SYSTEM_PMSET_SLEEP_LOG_TOKEN="system-pmset-sleep"
SYSTEM_PMSET_PORTABLE_SLEEP_SCOPE="-c"
SYSTEM_PMSET_NON_PORTABLE_SLEEP_SCOPE="-a"
SYSTEM_TIME_ZONE_AUTO_LOG_TOKEN="system-timezone-auto"
SYSTEM_TIME_ZONE_LOG_TOKEN="system-timezone"
SYSTEM_CLOCK_24_HOUR_LOG_TOKEN="system-clock-24-hour"
SSHD_PASSWORD_AUTHENTICATION=false
SSHD_KBD_INTERACTIVE_AUTHENTICATION=false
SSHD_CHALLENGE_RESPONSE_AUTHENTICATION=false
SSHD_PERMIT_ROOT_LOGIN=false
SSHD_PUBKEY_AUTHENTICATION=true
SSHD_X11_FORWARDING=false
SSHD_ALLOW_TCP_FORWARDING=false
SSHD_ALLOW_AGENT_FORWARDING=false
SYSTEM_REMOTE_LOGIN_LOG_TOKEN="system-remote-login"
SYSTEM_SSHD_CONFIG_LOG_TOKEN="system-sshd-config"
SYSTEM_SSHD_AUTHORIZED_KEY_LOG_TOKEN="system-sshd-authorized-key"
SYSTEM_SSHD_HOST_KEYS_LOG_TOKEN="system-sshd-host-keys"
SYSTEM_SSHD_CONFIG_DIR="$temp_dir/state/etc/ssh/sshd_config.d"
SYSTEM_SSHD_MANAGED_FILE_NAME="90-installations-and-configurations.conf"
SYSTEM_SSHD_AUTHORIZED_KEYS_DIR_NAME="authorized_keys.d"
SYSTEM_SSHD_HOST_ED25519_KEY_PATH="$temp_dir/state/etc/ssh/ssh_host_ed25519_key"
SYSTEM_SSHD_HOST_RSA_KEY_PATH="$temp_dir/state/etc/ssh/ssh_host_rsa_key"
SYSTEM_SSHD_HOST_ECDSA_KEY_PATH="$temp_dir/state/etc/ssh/ssh_host_ecdsa_key"
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

write_repo_ssh_key() {
  local temp_dir="$1"
  local file_name="$2"
  local public_key="$3"

  cat > "$temp_dir/keys/macos/ssh/$file_name" <<EOF
$public_key
EOF
}

managed_sshd_config_path() {
  local temp_dir="$1"
  printf '%s\n' "$temp_dir/state/etc/ssh/sshd_config.d/90-installations-and-configurations.conf"
}

managed_authorized_keys_dir() {
  local temp_dir="$1"
  printf '%s\n' "$temp_dir/home/ezirius/.ssh/authorized_keys.d"
}

host_key_path() {
  local temp_dir="$1"
  local key_name="$2"
  printf '%s\n' "$temp_dir/state/etc/ssh/$key_name"
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

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should succeed when no optional layered config files match'
  fi

  assert_not_contains "$output_file" 'Applying Dock settings' 'system-configure should skip Dock management when no optional settings are configured'
  assert_not_contains "$output_file" 'Applying power settings' 'system-configure should skip power management when no optional settings are configured'
  assert_not_contains "$output_file" 'Applying SSH settings' 'system-configure should skip SSH management when no optional settings are configured'
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

  cat > "$temp_dir/configs/shared/system/system-configure.conf" <<EOF
# Shared runtime support config for scripts/macos/system/system-configure.
SYSTEM_DOCK_DOMAIN="com.apple.dock"
SYSTEM_DOCK_AUTO_HIDE_KEY="autohide"
SYSTEM_DOCK_REORDER_SPACES_KEY="mru-spaces"
SYSTEM_DOCK_REORDER_SPACES_LOG_TOKEN="system-dock-mru-spaces"
SYSTEM_PMSET_AC_POWER_SECTION="AC Power"
SYSTEM_PMSET_SLEEP_LOG_TOKEN="system-pmset-sleep"
SYSTEM_PMSET_PORTABLE_SLEEP_SCOPE="-c"
SYSTEM_PMSET_NON_PORTABLE_SLEEP_SCOPE="-a"
SSHD_PASSWORD_AUTHENTICATION=false
SSHD_KBD_INTERACTIVE_AUTHENTICATION=false
SSHD_CHALLENGE_RESPONSE_AUTHENTICATION=false
SSHD_PERMIT_ROOT_LOGIN=false
SSHD_PUBKEY_AUTHENTICATION=true
SSHD_X11_FORWARDING=false
SSHD_ALLOW_TCP_FORWARDING=false
SSHD_ALLOW_AGENT_FORWARDING=false
SYSTEM_REMOTE_LOGIN_LOG_TOKEN="system-remote-login"
SYSTEM_SSHD_CONFIG_LOG_TOKEN="system-sshd-config"
SYSTEM_SSHD_AUTHORIZED_KEY_LOG_TOKEN="system-sshd-authorized-key"
SYSTEM_SSHD_HOST_KEYS_LOG_TOKEN="system-sshd-host-keys"
SYSTEM_SSHD_CONFIG_DIR="$temp_dir/state/etc/ssh/sshd_config.d"
SYSTEM_SSHD_MANAGED_FILE_NAME="90-installations-and-configurations.conf"
SYSTEM_SSHD_AUTHORIZED_KEYS_DIR_NAME="authorized_keys.d"
SYSTEM_SSHD_HOST_ED25519_KEY_PATH="$temp_dir/state/etc/ssh/ssh_host_ed25519_key"
SYSTEM_SSHD_HOST_RSA_KEY_PATH="$temp_dir/state/etc/ssh/ssh_host_rsa_key"
SYSTEM_SSHD_HOST_ECDSA_KEY_PATH="$temp_dir/state/etc/ssh/ssh_host_ecdsa_key"
EOF

  write_shared_shared_config "$temp_dir"

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'system-configure should fail when a required support config value is missing even if exported in the environment'
  fi

  assert_contains "$output_file" 'ERROR: Required config value is not set: SYSTEM_DOCK_AUTO_HIDE_LOG_TOKEN' 'system-configure should require support values to come from system-configure.conf itself'
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
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-dock-autohide,' 'logs Dock auto-hide change'
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-dock-mru-spaces,' 'logs Dock spaces change'
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-pmset-sleep,' 'logs pmset sleep change'
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
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-dock-mru-spaces,' 'logs the host-shared override application'
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
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-dock-autohide,' 'logs the host-user override application'
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
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-pmset-sleep,' 'logs changed non-portable pmset setting'
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
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-dock-mru-spaces,' 'logs the inherited partial override change'
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
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-pmset-sleep,' 'logs the portable sleep change'
}

test_disables_time_zone_auto_by_location_when_enabled() {
  local temp_dir
  local output_file
  local log_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  log_file="$temp_dir/logs/macos/shared/installations-and-configurations-maldoria.csv"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/defaults.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_macos_host_user_override "$temp_dir" 'maldoria' 'ezirius' 'TIME_ZONE_AUTO_BY_LOCATION=false'

  if ! TEST_TIME_ZONE_AUTO_CURRENT=1 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should disable automatic time zone selection when configured and currently enabled'
  fi

  assert_contains "$temp_dir/state/sudo.log" 'defaults write /Library/Preferences/com.apple.timezone.auto Active -bool false' 'disables automatic time zone by location when configured'
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-timezone-auto,' 'logs the automatic time zone change'
}

test_sets_time_zone_when_different() {
  local temp_dir
  local output_file
  local log_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  log_file="$temp_dir/logs/macos/shared/installations-and-configurations-maldoria.csv"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/systemsetup.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_macos_host_user_override "$temp_dir" 'maldoria' 'ezirius' 'TIME_ZONE="Africa/Johannesburg"'

  if ! TEST_TIME_ZONE_CURRENT='UTC' run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should set the configured timezone when it differs from the current machine state'
  fi

  assert_contains "$temp_dir/state/systemsetup.log" '-settimezone Africa/Johannesburg' 'sets the configured timezone when it differs'
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-timezone,' 'logs the timezone change'
}

test_enables_24_hour_clock_when_disabled() {
  local temp_dir
  local output_file
  local log_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  log_file="$temp_dir/logs/macos/shared/installations-and-configurations-maldoria.csv"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/killall.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_macos_host_user_override "$temp_dir" 'maldoria' 'ezirius' 'CLOCK_24_HOUR=true'

  if ! TEST_DEFAULTS_24_HOUR_CURRENT=0 TEST_DEFAULTS_12_HOUR_CURRENT=1 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should enable the 24-hour clock when configured and currently disabled'
  fi

  assert_contains "$temp_dir/state/defaults.log" 'write -g AppleICUForce24HourTime -bool true' 'enables the 24-hour clock preference when configured'
  assert_contains "$temp_dir/state/defaults.log" 'write -g AppleICUForce12HourTime -bool false' 'disables the 12-hour clock preference when enabling 24-hour time'
  assert_contains "$temp_dir/state/killall.log" 'cfprefsd' 'restarts cfprefsd after changing the 24-hour clock preference'
  assert_contains "$temp_dir/state/killall.log" 'SystemUIServer' 'restarts SystemUIServer after changing the 24-hour clock preference'
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-clock-24-hour,' 'logs the 24-hour clock change'
}

test_rejects_invalid_time_zone_value() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_macos_host_user_override "$temp_dir" 'maldoria' 'ezirius' 'TIME_ZONE="Mars/Phobos"'

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'system-configure should reject invalid timezone values before applying changes'
  fi

  assert_contains "$output_file" 'ERROR: Invalid TIME_ZONE value: Mars/Phobos' 'fails clearly when an invalid timezone is configured'
}

test_generates_missing_ed25519_host_key() {
  local temp_dir
  local output_file
  local log_file
  local host_key_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  log_file="$temp_dir/logs/macos/shared/installations-and-configurations-maldoria.csv"
  host_key_file="$(host_key_path "$temp_dir" 'ssh_host_ed25519_key')"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  : > "$temp_dir/state/systemsetup.log"
  : > "$temp_dir/state/sshd.log"
  : > "$temp_dir/state/launchctl.log"
  : > "$temp_dir/state/ssh-keygen.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"

  if ! TEST_HOST_KEY_DIR="$temp_dir/state/etc/ssh" TEST_REMOTE_LOGIN_CURRENT=Off TEST_DEFAULTS_AUTO_HIDE_CURRENT=1 TEST_DEFAULTS_MRU_SPACES_CURRENT=0 TEST_PMSET_CURRENT_SLEEP=0 TEST_PMSET_PORTABLE=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should generate a missing Ed25519 host key'
  fi

  assert_contains "$temp_dir/state/ssh-keygen.log" '-A' 'runs ssh-keygen -A when the Ed25519 host key is missing'
  assert_contains "$host_key_file" 'host-private-key' 'creates the Ed25519 host private key'
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-sshd-host-keys,' 'logs host key generation changes'
}

test_fails_clearly_when_ed25519_host_key_generation_does_not_produce_key() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  : > "$temp_dir/state/systemsetup.log"
  : > "$temp_dir/state/sshd.log"
  : > "$temp_dir/state/launchctl.log"
  : > "$temp_dir/state/ssh-keygen.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"

  if TEST_HOST_KEY_DIR="$temp_dir/state/etc/ssh" TEST_SSH_KEYGEN_CREATE_ED25519=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'system-configure should fail if host key generation does not produce the Ed25519 host key'
  fi

  assert_contains "$output_file" 'ERROR: Required SSH host key is missing after generation:' 'fails clearly when Ed25519 host key is still missing after generation'
}

test_removes_non_ed25519_host_keys_even_when_ssh_is_disabled() {
  local temp_dir
  local output_file
  local log_file
  local rsa_key_path
  local ecdsa_key_path

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  log_file="$temp_dir/logs/macos/shared/installations-and-configurations-maldoria.csv"
  rsa_key_path="$(host_key_path "$temp_dir" 'ssh_host_rsa_key')"
  ecdsa_key_path="$(host_key_path "$temp_dir" 'ssh_host_ecdsa_key')"
  mkdir -p "$temp_dir/state/etc/ssh"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  : > "$temp_dir/state/systemsetup.log"
  : > "$temp_dir/state/sshd.log"
  : > "$temp_dir/state/launchctl.log"
  : > "$temp_dir/state/ssh-keygen.log"
  printf 'ed-private\n' > "$(host_key_path "$temp_dir" 'ssh_host_ed25519_key')"
  printf 'ed-public\n' > "$(host_key_path "$temp_dir" 'ssh_host_ed25519_key').pub"
  printf 'rsa-private\n' > "$rsa_key_path"
  printf 'rsa-public\n' > "$rsa_key_path.pub"
  printf 'ecdsa-private\n' > "$ecdsa_key_path"
  printf 'ecdsa-public\n' > "$ecdsa_key_path.pub"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"

  if ! TEST_HOST_KEY_DIR="$temp_dir/state/etc/ssh" TEST_REMOTE_LOGIN_CURRENT=Off TEST_DEFAULTS_AUTO_HIDE_CURRENT=1 TEST_DEFAULTS_MRU_SPACES_CURRENT=0 TEST_PMSET_CURRENT_SLEEP=0 TEST_PMSET_PORTABLE=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should prune non-Ed25519 host keys even when SSH login is disabled'
  fi

  [[ ! -e "$rsa_key_path" ]] || fail 'removes RSA host key when converging to Ed25519-only host keys'
  [[ ! -e "$rsa_key_path.pub" ]] || fail 'removes RSA host public key when converging to Ed25519-only host keys'
  [[ ! -e "$ecdsa_key_path" ]] || fail 'removes ECDSA host key when converging to Ed25519-only host keys'
  [[ ! -e "$ecdsa_key_path.pub" ]] || fail 'removes ECDSA host public key when converging to Ed25519-only host keys'
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-sshd-host-keys,' 'logs host key pruning changes'
}

test_ssh_enabled_requires_sshd_allow_users_to_equal_ezirius() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"
  write_repo_ssh_key "$temp_dir" 'maldoria-ipirus-ezirius-login.pub' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILI8TJ8jr2QiBXLPSxC3OqgRCjlfCFvDNQej4t0uey6t'
  write_macos_host_user_override "$temp_dir" 'maldoria' 'ezirius' 'SSH_REMOTE_LOGIN_ENABLED=true
SSHD_ALLOW_USERS="otheruser"
SSHD_LOGIN_KEY_FILES="maldoria-ipirus-ezirius-login.pub"'

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'system-configure should require SSHD_ALLOW_USERS to equal ezirius when SSH is enabled'
  fi

  assert_contains "$output_file" 'ERROR: SSHD_ALLOW_USERS must be exactly ezirius when SSH_REMOTE_LOGIN_ENABLED is true' 'fails clearly when enabled SSH does not equal ezirius'
}

test_ssh_enabled_rejects_multiple_allowed_users_in_first_pass() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"
  write_repo_ssh_key "$temp_dir" 'maldoria-ipirus-ezirius-login.pub' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILI8TJ8jr2QiBXLPSxC3OqgRCjlfCFvDNQej4t0uey6t'
  write_macos_host_user_override "$temp_dir" 'maldoria' 'ezirius' 'SSH_REMOTE_LOGIN_ENABLED=true
SSHD_ALLOW_USERS="ezirius otheruser"
SSHD_LOGIN_KEY_FILES="maldoria-ipirus-ezirius-login.pub"'

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'system-configure should reject multiple allowed users in the first SSH management pass'
  fi

  assert_contains "$output_file" 'ERROR: SSHD_ALLOW_USERS must be exactly ezirius when SSH_REMOTE_LOGIN_ENABLED is true' 'fails clearly when enabled SSH allows more than ezirius in the first pass'
}

test_ssh_enabled_requires_sshd_login_key_files() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"
  write_macos_host_user_override "$temp_dir" 'maldoria' 'ezirius' 'SSH_REMOTE_LOGIN_ENABLED=true
SSHD_ALLOW_USERS="ezirius"'

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'system-configure should require SSHD_LOGIN_KEY_FILES when SSH is enabled'
  fi

  assert_contains "$output_file" 'ERROR: SSHD_LOGIN_KEY_FILES must be set when SSH_REMOTE_LOGIN_ENABLED is true' 'fails clearly when enabled SSH has no configured key files'
}

test_ssh_enabled_deploys_maldoria_keys_with_exact_pub_filenames() {
  local temp_dir
  local output_file
  local log_file
  local sshd_config_path
  local authorized_keys_dir

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  log_file="$temp_dir/logs/macos/shared/installations-and-configurations-maldoria.csv"
  sshd_config_path="$(managed_sshd_config_path "$temp_dir")"
  authorized_keys_dir="$(managed_authorized_keys_dir "$temp_dir")"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  : > "$temp_dir/state/systemsetup.log"
  : > "$temp_dir/state/sshd.log"
  : > "$temp_dir/state/launchctl.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"
  write_repo_ssh_key "$temp_dir" 'maldoria-ipirus-ezirius-login.pub' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILI8TJ8jr2QiBXLPSxC3OqgRCjlfCFvDNQej4t0uey6t'
  write_repo_ssh_key "$temp_dir" 'maldoria-iparia-ezirius-login.pub' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOGqvd39EeXgfGhLRNoOXJYTkc0wbw825urpZKW+KiUR'
  write_macos_host_user_override "$temp_dir" 'maldoria' 'ezirius' 'SSH_REMOTE_LOGIN_ENABLED=true
SSHD_ALLOW_USERS="ezirius"
SSHD_LOGIN_KEY_FILES="maldoria-ipirus-ezirius-login.pub maldoria-iparia-ezirius-login.pub"'

  if ! TEST_REMOTE_LOGIN_CURRENT=Off TEST_DEFAULTS_AUTO_HIDE_CURRENT=1 TEST_DEFAULTS_MRU_SPACES_CURRENT=0 TEST_PMSET_CURRENT_SLEEP=0 TEST_PMSET_PORTABLE=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should enable SSH and deploy configured maldoria keys'
  fi

  assert_contains "$temp_dir/state/systemsetup.log" '-setremotelogin on' 'enables Remote Login when SSH is enabled'
  assert_contains "$sshd_config_path" 'AllowUsers ezirius' 'renders AllowUsers for ezirius'
  assert_contains "$sshd_config_path" 'AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys.d/*' 'renders authorized keys directory support'
  assert_contains "$sshd_config_path" 'PasswordAuthentication no' 'renders hardened password authentication setting'
  assert_contains "$authorized_keys_dir/maldoria-ipirus-ezirius-login.pub" 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILI8TJ8jr2QiBXLPSxC3OqgRCjlfCFvDNQej4t0uey6t' 'deploys the first maldoria key with exact .pub filename'
  assert_contains "$authorized_keys_dir/maldoria-iparia-ezirius-login.pub" 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOGqvd39EeXgfGhLRNoOXJYTkc0wbw825urpZKW+KiUR' 'deploys the second maldoria key with exact .pub filename'
  assert_contains "$temp_dir/state/sshd.log" '-t' 'validates sshd configuration before reload'
  assert_not_contains "$temp_dir/state/launchctl.log" 'kickstart -k system/com.openssh.sshd' 'does not reload sshd when Remote Login is being enabled from an off state'
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-remote-login,' 'logs the Remote Login enablement change'
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-sshd-config,' 'logs the sshd config change'
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-sshd-authorized-key,' 'logs the authorized key deployment change'
}

test_ssh_config_change_reloads_sshd_when_remote_login_is_already_enabled() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  : > "$temp_dir/state/systemsetup.log"
  : > "$temp_dir/state/sshd.log"
  : > "$temp_dir/state/launchctl.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"
  write_repo_ssh_key "$temp_dir" 'maldoria-ipirus-ezirius-login.pub' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILI8TJ8jr2QiBXLPSxC3OqgRCjlfCFvDNQej4t0uey6t'
  write_macos_host_user_override "$temp_dir" 'maldoria' 'ezirius' 'SSH_REMOTE_LOGIN_ENABLED=true
SSHD_ALLOW_USERS="ezirius"
SSHD_LOGIN_KEY_FILES="maldoria-ipirus-ezirius-login.pub"'

  if ! TEST_REMOTE_LOGIN_CURRENT=On TEST_DEFAULTS_AUTO_HIDE_CURRENT=1 TEST_DEFAULTS_MRU_SPACES_CURRENT=0 TEST_PMSET_CURRENT_SLEEP=0 TEST_PMSET_PORTABLE=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should reload sshd when the managed SSH config changes while Remote Login is already enabled'
  fi

  assert_contains "$temp_dir/state/sshd.log" '-t' 'validates sshd configuration before reload when Remote Login is already enabled'
  assert_contains "$temp_dir/state/launchctl.log" 'kickstart -k system/com.openssh.sshd' 'reloads sshd when the managed config changes and Remote Login is already enabled'
}

test_ssh_enabled_deploys_maravyn_keys_with_exact_pub_filenames() {
  local temp_dir
  local output_file
  local authorized_keys_dir

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  authorized_keys_dir="$(managed_authorized_keys_dir "$temp_dir")"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  : > "$temp_dir/state/systemsetup.log"
  : > "$temp_dir/state/sshd.log"
  : > "$temp_dir/state/launchctl.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"
  write_repo_ssh_key "$temp_dir" 'maravyn-maldoria-ezirius-login.pub' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICSqWNpR0r6JR8U0WpEukrkXvnax3sECll3PtKDviLGf'
  write_repo_ssh_key "$temp_dir" 'maravyn-ipirus-ezirius-login.pub' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIESP2Js7TQIZ6RAeLFHJrF5dYJ4id/Crey/FkDmx991c'
  write_repo_ssh_key "$temp_dir" 'maravyn-iparia-ezirius-login.pub' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO/0nCy2P4evAkplHUCmuzyCu94LvjqDCyxU2K5p1ONu'
  write_macos_host_user_override "$temp_dir" 'maravyn' 'ezirius' 'SSH_REMOTE_LOGIN_ENABLED=true
SSHD_ALLOW_USERS="ezirius"
SSHD_LOGIN_KEY_FILES="maravyn-maldoria-ezirius-login.pub maravyn-ipirus-ezirius-login.pub maravyn-iparia-ezirius-login.pub"'

  if ! TEST_HOSTNAME=maravyn.local TEST_REMOTE_LOGIN_CURRENT=On TEST_DEFAULTS_AUTO_HIDE_CURRENT=1 TEST_DEFAULTS_MRU_SPACES_CURRENT=0 TEST_PMSET_CURRENT_SLEEP=0 TEST_PMSET_PORTABLE=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should deploy the configured maravyn keys'
  fi

  assert_contains "$authorized_keys_dir/maravyn-maldoria-ezirius-login.pub" 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICSqWNpR0r6JR8U0WpEukrkXvnax3sECll3PtKDviLGf' 'deploys the first maravyn key with exact .pub filename'
  assert_contains "$authorized_keys_dir/maravyn-ipirus-ezirius-login.pub" 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIESP2Js7TQIZ6RAeLFHJrF5dYJ4id/Crey/FkDmx991c' 'deploys the second maravyn key with exact .pub filename'
  assert_contains "$authorized_keys_dir/maravyn-iparia-ezirius-login.pub" 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO/0nCy2P4evAkplHUCmuzyCu94LvjqDCyxU2K5p1ONu' 'deploys the third maravyn key with exact .pub filename'
}

test_ssh_key_sync_removes_stale_managed_keys_not_in_current_config() {
  local temp_dir
  local output_file
  local authorized_keys_dir

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  authorized_keys_dir="$(managed_authorized_keys_dir "$temp_dir")"
  mkdir -p "$temp_dir/state" "$authorized_keys_dir"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  : > "$temp_dir/state/systemsetup.log"
  : > "$temp_dir/state/sshd.log"
  : > "$temp_dir/state/launchctl.log"
  printf 'old-key\n' > "$authorized_keys_dir/maldoria-ipirus-ezirius-login.pub"
  printf 'stale-key\n' > "$authorized_keys_dir/maldoria-iparia-ezirius-login.pub"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"
  write_repo_ssh_key "$temp_dir" 'maldoria-ipirus-ezirius-login.pub' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILI8TJ8jr2QiBXLPSxC3OqgRCjlfCFvDNQej4t0uey6t'
  write_macos_host_user_override "$temp_dir" 'maldoria' 'ezirius' 'SSH_REMOTE_LOGIN_ENABLED=true
SSHD_ALLOW_USERS="ezirius"
SSHD_LOGIN_KEY_FILES="maldoria-ipirus-ezirius-login.pub"'

  if ! TEST_REMOTE_LOGIN_CURRENT=On TEST_DEFAULTS_AUTO_HIDE_CURRENT=1 TEST_DEFAULTS_MRU_SPACES_CURRENT=0 TEST_PMSET_CURRENT_SLEEP=0 TEST_PMSET_PORTABLE=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should remove stale managed SSH keys that are no longer configured'
  fi

  assert_contains "$authorized_keys_dir/maldoria-ipirus-ezirius-login.pub" 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILI8TJ8jr2QiBXLPSxC3OqgRCjlfCFvDNQej4t0uey6t' 'keeps currently configured managed key'
  [[ ! -e "$authorized_keys_dir/maldoria-iparia-ezirius-login.pub" ]] || fail 'removes stale managed key not present in current SSHD_LOGIN_KEY_FILES'
}

test_ssh_disabled_removes_managed_files() {
  local temp_dir
  local output_file
  local sshd_config_path
  local authorized_keys_dir
  local log_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  sshd_config_path="$(managed_sshd_config_path "$temp_dir")"
  authorized_keys_dir="$(managed_authorized_keys_dir "$temp_dir")"
  log_file="$temp_dir/logs/macos/shared/installations-and-configurations-maldoria.csv"
  mkdir -p "$temp_dir/state" "$authorized_keys_dir" "$(dirname "$sshd_config_path")"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  : > "$temp_dir/state/systemsetup.log"
  : > "$temp_dir/state/sshd.log"
  : > "$temp_dir/state/launchctl.log"
  printf 'old-config\n' > "$sshd_config_path"
  printf 'old-key\n' > "$authorized_keys_dir/maldoria-ipirus-ezirius-login.pub"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"
  write_repo_ssh_key "$temp_dir" 'maldoria-ipirus-ezirius-login.pub' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILI8TJ8jr2QiBXLPSxC3OqgRCjlfCFvDNQej4t0uey6t'
  write_macos_host_user_override "$temp_dir" 'maldoria' 'ezirius' 'SSH_REMOTE_LOGIN_ENABLED=false'

  if ! TEST_REMOTE_LOGIN_CURRENT=On TEST_DEFAULTS_AUTO_HIDE_CURRENT=1 TEST_DEFAULTS_MRU_SPACES_CURRENT=0 TEST_PMSET_CURRENT_SLEEP=0 TEST_PMSET_PORTABLE=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should disable SSH and remove managed SSH files when SSH is disabled'
  fi

  assert_contains "$temp_dir/state/systemsetup.log" '-setremotelogin off' 'disables Remote Login when SSH is disabled'
  [[ ! -e "$sshd_config_path" ]] || fail 'removes the managed sshd drop-in when SSH is disabled'
  [[ ! -e "$authorized_keys_dir/maldoria-ipirus-ezirius-login.pub" ]] || fail 'removes the managed authorized key file when SSH is disabled'
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-remote-login,' 'logs the Remote Login disablement change'
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-sshd-config,' 'logs the sshd config removal'
  assert_contains "$log_file" '20260427,143015,maldoria,Configured,system-sshd-authorized-key,' 'logs the authorized key removal'
}

test_ssh_key_sync_does_not_reload_sshd_when_drop_in_is_unchanged() {
  local temp_dir
  local output_file
  local sshd_config_path
  local authorized_keys_dir

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  sshd_config_path="$(managed_sshd_config_path "$temp_dir")"
  authorized_keys_dir="$(managed_authorized_keys_dir "$temp_dir")"
  mkdir -p "$temp_dir/state" "$authorized_keys_dir" "$(dirname "$sshd_config_path")"
  : > "$temp_dir/state/defaults.log"
  : > "$temp_dir/state/pmset.log"
  : > "$temp_dir/state/sudo.log"
  : > "$temp_dir/state/killall.log"
  : > "$temp_dir/state/systemsetup.log"
  : > "$temp_dir/state/sshd.log"
  : > "$temp_dir/state/launchctl.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  write_shared_shared_config "$temp_dir"
  write_repo_ssh_key "$temp_dir" 'maldoria-ipirus-ezirius-login.pub' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILI8TJ8jr2QiBXLPSxC3OqgRCjlfCFvDNQej4t0uey6t'
  write_macos_host_user_override "$temp_dir" 'maldoria' 'ezirius' 'SSH_REMOTE_LOGIN_ENABLED=true
SSHD_ALLOW_USERS="ezirius"
SSHD_LOGIN_KEY_FILES="maldoria-ipirus-ezirius-login.pub"'

  cat > "$sshd_config_path" <<EOF
HostKey $temp_dir/state/etc/ssh/ssh_host_ed25519_key
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
AllowUsers ezirius
AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys.d/*
EOF
  printf 'ed-private\n' > "$(host_key_path "$temp_dir" 'ssh_host_ed25519_key')"
  printf 'ed-public\n' > "$(host_key_path "$temp_dir" 'ssh_host_ed25519_key').pub"
  printf 'stale-key\n' > "$authorized_keys_dir/maldoria-ipirus-ezirius-login.pub"

  if ! TEST_REMOTE_LOGIN_CURRENT=On TEST_DEFAULTS_AUTO_HIDE_CURRENT=1 TEST_DEFAULTS_MRU_SPACES_CURRENT=0 TEST_PMSET_CURRENT_SLEEP=0 TEST_PMSET_PORTABLE=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'system-configure should update SSH keys without reloading sshd when the drop-in is unchanged'
  fi

  assert_not_contains "$temp_dir/state/launchctl.log" 'kickstart -k system/com.openssh.sshd' 'does not reload sshd when only managed key content changes'
  assert_not_contains "$temp_dir/state/systemsetup.log" '-setremotelogin on' 'does not re-enable Remote Login when it is already enabled'
}

test_documentation_headers() {
  assert_starts_with_comment "$ROOT/configs/shared/system/system-configure.conf" 'shared system support config should start with a header comment'
  assert_starts_with_comment "$ROOT/configs/shared/system/system-shared-shared.conf" 'shared shared system config should start with a header comment'
  assert_starts_with_comment "$ROOT/configs/macos/system/system-maldoria-shared.conf" 'host-shared macOS system config should start with a header comment'
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
test_disables_time_zone_auto_by_location_when_enabled
test_sets_time_zone_when_different
test_enables_24_hour_clock_when_disabled
test_rejects_invalid_time_zone_value
test_generates_missing_ed25519_host_key
test_fails_clearly_when_ed25519_host_key_generation_does_not_produce_key
test_removes_non_ed25519_host_keys_even_when_ssh_is_disabled
test_ssh_enabled_requires_sshd_allow_users_to_equal_ezirius
test_ssh_enabled_rejects_multiple_allowed_users_in_first_pass
test_ssh_enabled_requires_sshd_login_key_files
test_ssh_enabled_deploys_maldoria_keys_with_exact_pub_filenames
test_ssh_enabled_deploys_maravyn_keys_with_exact_pub_filenames
test_ssh_config_change_reloads_sshd_when_remote_login_is_already_enabled
test_ssh_key_sync_removes_stale_managed_keys_not_in_current_config
test_ssh_disabled_removes_managed_files
test_ssh_key_sync_does_not_reload_sshd_when_drop_in_is_unchanged
test_documentation_headers

printf 'PASS: tests/shared/system/test-system-configure.sh\n'
