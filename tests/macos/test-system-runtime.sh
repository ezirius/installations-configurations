#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
STATE_DIR="$TMPDIR/state"
MOCK_BIN="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"
mkdir -p "$REPO_DIR/scripts/macos" "$REPO_DIR/lib/shell" "$REPO_DIR/config/system" "$STATE_DIR" "$MOCK_BIN" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers"
trap 'rm -rf "$TMPDIR"' EXIT

cp "$ROOT/scripts/macos/system-configure" "$REPO_DIR/scripts/macos/system-configure"
cp "$ROOT/lib/shell/common.sh" "$REPO_DIR/lib/shell/common.sh"
cp "$ROOT/config/system/shared-macos.conf" "$REPO_DIR/config/system/shared-macos.conf"
cat > "$REPO_DIR/config/system/maldoria-macos.conf" <<'EOF'
DOCK_AUTOHIDE=false
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

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" DOCK_AUTOHIDE_STATE=1 DOCK_MRU_STATE=1 "$REPO_DIR/scripts/macos/system-configure" >/dev/null
assert_contains "$STATE_DIR/defaults.log" 'write com.apple.dock autohide -bool 0' 'host system config overrides shared dock autohide'
assert_contains "$STATE_DIR/defaults.log" 'write com.apple.dock mru-spaces -bool 0' 'shared system config disables dock space rearranging'
assert_contains "$STATE_DIR/pmset.log" '-c sleep 0' 'portable Macs use AC-only pmset sleep control'
assert_contains "$STATE_DIR/killall.log" 'Dock' 'Dock is restarted when Dock settings change'

STATE_DIR_NOOP="$TMPDIR/state-noop"
mkdir -p "$STATE_DIR_NOOP" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR_NOOP" DOCK_AUTOHIDE_STATE=0 DOCK_MRU_STATE=0 PMSET_SLEEP_STATE=0 "$REPO_DIR/scripts/macos/system-configure" >/dev/null
if [[ -f "$STATE_DIR_NOOP/defaults.log" || -f "$STATE_DIR_NOOP/killall.log" || -f "$STATE_DIR_NOOP/pmset.log" ]]; then
  printf 'assertion failed: system-configure should not rewrite Dock or pmset settings when values already match\n' >&2
  exit 1
fi

echo "System runtime checks passed"
