#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
STATE_DIR="$TMPDIR/state"
MOCK_BIN="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"
mkdir -p "$REPO_DIR/scripts/system/macos" "$REPO_DIR/lib/shell" "$REPO_DIR/lib/shell/shared" "$REPO_DIR/config/system/macos" "$REPO_DIR/config/repo/shared" "$STATE_DIR" "$MOCK_BIN" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers"
trap 'rm -rf "$TMPDIR"' EXIT

cp "$ROOT/scripts/system/macos/system-configure" "$REPO_DIR/scripts/system/macos/system-configure"
cp "$ROOT/lib/shell/shared/common.sh" "$REPO_DIR/lib/shell/shared/common.sh"
cp "$ROOT/config/repo/shared/repo-settings-shared.conf" "$REPO_DIR/config/repo/shared/repo-settings-shared.conf"
cp "$ROOT/config/system/macos/system-settings-shared.conf" "$REPO_DIR/config/system/macos/system-settings-shared.conf"
cat > "$REPO_DIR/config/system/macos/system-settings-maldoria.conf" <<'EOF'
DOCK_AUTO_HIDE=false
DOCK_REORDER_SPACES_BY_RECENT_USE=true
AC_POWER_SYSTEM_SLEEP_MINUTES=30
SYSTEM_DOCK_DOMAIN="com.apple.dock"
SYSTEM_DOCK_AUTO_HIDE_KEY="autohide"
SYSTEM_DOCK_REORDER_SPACES_KEY="mru-spaces"
SYSTEM_PMSET_AC_POWER_SECTION="AC Power"
SYSTEM_PMSET_PORTABLE_SLEEP_SCOPE="-c"
SYSTEM_PMSET_NON_PORTABLE_SLEEP_SCOPE="-a"
EOF

assert_contains() {
  local file="$1" needle="$2" message="$3"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nmissing: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
cat > "$MOCK_BIN/scutil" <<'EOF'
#!/usr/bin/env bash
printf 'Maldoria.local\n'
EOF
cat > "$MOCK_BIN/xcode-select" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -p ]]
printf '/Library/Developer/CommandLineTools\n'
EOF
cat > "$MOCK_BIN/defaults" <<EOF
#!/usr/bin/env bash
STATE_DIR="\${STATE_DIR:?}"
if [[ "\$1" == read ]]; then
  case "\$3" in
    autohide) printf '%s\n' "\${DOCK_AUTOHIDE_STATE:-1}" ;;
    mru-spaces) printf '%s\n' "\${DOCK_MRU_STATE:-1}" ;;
  esac
elif [[ "\$1" == write ]]; then
  if [[ "\$4" == -bool && "\$5" != true && "\$5" != false ]]; then
    printf 'defaults bool expects true/false\n' >&2
    exit 1
  fi
  printf '%s\n' "\$*" >> "\$STATE_DIR/defaults.log"
fi
EOF
cat > "$MOCK_BIN/pmset" <<'EOF'
#!/usr/bin/env bash
STATE_DIR="${STATE_DIR:?}"
if [[ "$1 $2" == '-g batt' ]]; then
  printf 'Now drawing from InternalBattery-0\n'
elif [[ "$1 $2" == '-g custom' ]]; then
  printf 'AC Power:\n sleep %s\n' "${PMSET_SLEEP_STATE:-1}"
else
  printf '%s\n' "$*" >> "$STATE_DIR/pmset.log"
fi
EOF
cat > "$MOCK_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/sudo.log"
if [[ "$1" == -v ]]; then
  exit 0
fi
exec "$@"
EOF
cat > "$MOCK_BIN/killall" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STATE_DIR/killall.log"
EOF
cat > "$MOCK_BIN/grep" <<'EOF'
#!/usr/bin/env bash
exec /bin/grep "$@"
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/scutil" "$MOCK_BIN/xcode-select" "$MOCK_BIN/defaults" "$MOCK_BIN/pmset" "$MOCK_BIN/sudo" "$MOCK_BIN/killall" "$MOCK_BIN/grep"

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" DOCK_AUTOHIDE_STATE=1 DOCK_MRU_STATE=0 "$REPO_DIR/scripts/system/macos/system-configure" >/dev/null
assert_contains "$STATE_DIR/defaults.log" 'write com.apple.dock autohide -bool false' 'host system config overrides shared dock autohide'
assert_contains "$STATE_DIR/defaults.log" 'write com.apple.dock mru-spaces -bool true' 'host system config layers over the shared fallback when present'
assert_contains "$STATE_DIR/sudo.log" '-v' 'system-configure refreshes sudo before applying pmset changes'
assert_contains "$STATE_DIR/pmset.log" '-c sleep 30' 'portable Macs use the host-specific sleep setting when present'
assert_contains "$STATE_DIR/killall.log" 'Dock' 'Dock is restarted when Dock settings change'

cat > "$REPO_DIR/config/system/macos/system-settings-maldoria.conf" <<'EOF'
DOCK_AUTO_HIDE=false
EOF

STATE_DIR_INCOMPLETE="$TMPDIR/state-incomplete-host"
mkdir -p "$STATE_DIR_INCOMPLETE"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR_INCOMPLETE" DOCK_AUTOHIDE_STATE=1 DOCK_MRU_STATE=1 "$REPO_DIR/scripts/system/macos/system-configure" >/dev/null
assert_contains "$STATE_DIR_INCOMPLETE/defaults.log" 'write com.apple.dock autohide -bool false' 'host-specific system config can override one value while inheriting shared defaults'
assert_contains "$STATE_DIR_INCOMPLETE/pmset.log" '-c sleep 0' 'incomplete host config inherits shared pmset defaults'

cat > "$REPO_DIR/config/system/macos/system-settings-maldoria.conf" <<'EOF'
DOCK_AUTO_HIDE=false
DOCK_REORDER_SPACES_BY_RECENT_USE=true
AC_POWER_SYSTEM_SLEEP_MINUTES=30
SYSTEM_DOCK_AUTO_HIDE_KEY="autohide"
SYSTEM_DOCK_REORDER_SPACES_KEY="mru-spaces"
SYSTEM_PMSET_AC_POWER_SECTION="AC Power"
SYSTEM_PMSET_PORTABLE_SLEEP_SCOPE="-c"
SYSTEM_PMSET_NON_PORTABLE_SLEEP_SCOPE="-a"
EOF

STATE_DIR_MISSING_METADATA="$TMPDIR/state-missing-metadata"
mkdir -p "$STATE_DIR_MISSING_METADATA"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR_MISSING_METADATA" DOCK_AUTOHIDE_STATE=1 DOCK_MRU_STATE=0 "$REPO_DIR/scripts/system/macos/system-configure" >/dev/null
assert_contains "$STATE_DIR_MISSING_METADATA/defaults.log" 'write com.apple.dock autohide -bool false' 'host-specific system config can inherit shared metadata keys'
assert_contains "$STATE_DIR_MISSING_METADATA/pmset.log" '-c sleep 30' 'host-specific system config still overrides shared pmset values'

cat > "$REPO_DIR/config/system/macos/system-settings-maldoria.conf" <<'EOF'
DOCK_AUTO_HIDE=false
DOCK_REORDER_SPACES_BY_RECENT_USE=true
AC_POWER_SYSTEM_SLEEP_MINUTES=30
SYSTEM_DOCK_DOMAIN="com.apple.dock"
SYSTEM_DOCK_AUTO_HIDE_KEY="autohide"
SYSTEM_DOCK_REORDER_SPACES_KEY="mru-spaces"
SYSTEM_PMSET_AC_POWER_SECTION="AC Power"
SYSTEM_PMSET_PORTABLE_SLEEP_SCOPE="-c"
SYSTEM_PMSET_NON_PORTABLE_SLEEP_SCOPE="-a"
EOF

rm -f "$REPO_DIR/config/system/macos/system-settings-maldoria.conf"

rm -f "$REPO_DIR/config/system/macos/system-settings-shared.conf"

cat > "$REPO_DIR/config/system/macos/system-settings-maldoria.conf" <<'EOF'
DOCK_AUTO_HIDE=false
DOCK_REORDER_SPACES_BY_RECENT_USE=true
AC_POWER_SYSTEM_SLEEP_MINUTES=30
SYSTEM_DOCK_DOMAIN="com.apple.dock"
SYSTEM_DOCK_AUTO_HIDE_KEY="autohide"
SYSTEM_DOCK_REORDER_SPACES_KEY="mru-spaces"
SYSTEM_PMSET_AC_POWER_SECTION="AC Power"
SYSTEM_PMSET_PORTABLE_SLEEP_SCOPE="-c"
SYSTEM_PMSET_NON_PORTABLE_SLEEP_SCOPE="-a"
EOF

STATE_DIR_HOST_ONLY="$TMPDIR/state-host-only"
mkdir -p "$STATE_DIR_HOST_ONLY"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR_HOST_ONLY" DOCK_AUTOHIDE_STATE=1 DOCK_MRU_STATE=0 "$REPO_DIR/scripts/system/macos/system-configure" >/dev/null
assert_contains "$STATE_DIR_HOST_ONLY/defaults.log" 'write com.apple.dock autohide -bool false' 'system-configure works with a host-specific config only'
assert_contains "$STATE_DIR_HOST_ONLY/defaults.log" 'write com.apple.dock mru-spaces -bool true' 'host-only config still applies all configured dock values'
assert_contains "$STATE_DIR_HOST_ONLY/pmset.log" '-c sleep 30' 'host-only config still applies power settings'

rm -f "$REPO_DIR/config/system/macos/system-settings-maldoria.conf"

STATE_DIR_SHARED="$TMPDIR/state-shared-fallback"
mkdir -p "$STATE_DIR_SHARED"
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR_SHARED" DOCK_AUTOHIDE_STATE=0 DOCK_MRU_STATE=1 "$REPO_DIR/scripts/system/macos/system-configure" >/dev/null 2>"$STATE_DIR_SHARED/err"; then
  printf 'assertion failed: system-configure should fail clearly when neither shared nor host config exists and required values are missing\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR_SHARED/err" 'DOCK_AUTO_HIDE is not set in the managed macOS system config' 'system-configure reports missing final required values when no config files exist'

cp "$ROOT/config/system/macos/system-settings-shared.conf" "$REPO_DIR/config/system/macos/system-settings-shared.conf"

STATE_DIR_NOOP="$TMPDIR/state-noop"
mkdir -p "$STATE_DIR_NOOP" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR_NOOP" DOCK_AUTOHIDE_STATE=1 DOCK_MRU_STATE=0 PMSET_SLEEP_STATE=0 "$REPO_DIR/scripts/system/macos/system-configure" >/dev/null
if [[ -f "$STATE_DIR_NOOP/defaults.log" || -f "$STATE_DIR_NOOP/killall.log" || -f "$STATE_DIR_NOOP/pmset.log" || -f "$STATE_DIR_NOOP/sudo.log" ]]; then
  printf 'assertion failed: system-configure should not rewrite Dock, pmset, or refresh sudo when values already match\n' >&2
  exit 1
fi

STATE_DIR_DESKTOP="$TMPDIR/state-desktop"
mkdir -p "$STATE_DIR_DESKTOP"
cat > "$MOCK_BIN/pmset" <<'EOF'
#!/usr/bin/env bash
STATE_DIR="${STATE_DIR:?}"
if [[ "$1 $2" == '-g batt' ]]; then
  printf 'No battery installed\n'
elif [[ "$1 $2" == '-g custom' ]]; then
  printf 'AC Power:\n sleep %s\n' "${PMSET_SLEEP_STATE:-1}"
else
  printf '%s\n' "$*" >> "$STATE_DIR/pmset.log"
fi
EOF
chmod +x "$MOCK_BIN/pmset"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR_DESKTOP" DOCK_AUTOHIDE_STATE=0 DOCK_MRU_STATE=0 PMSET_SLEEP_STATE=1 "$REPO_DIR/scripts/system/macos/system-configure" >/dev/null
assert_contains "$STATE_DIR_DESKTOP/pmset.log" '-a sleep 0' 'desktop Macs use the default pmset scope'

echo "System runtime checks passed"
