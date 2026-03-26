#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/iterm2-configure"
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
HOME_DIR="$TMPDIR/home"
mkdir -p "$MOCK_BIN" "$STATE_DIR" "$HOME_DIR/Library/Preferences" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers"
trap 'rm -rf "$TMPDIR"' EXIT

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

cat > "$MOCK_BIN/defaults" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
cmd="$1"
domain="$2"
key="$3"
state_file="$STATE_DIR/${domain}.${key}"
case "$cmd" in
  read)
    [[ -f "$state_file" ]] && cat "$state_file" || exit 1
    ;;
  write)
    [[ "$4" == -bool ]] || exit 1
    printf '%s\n' "$5" > "$state_file"
    ;;
  *) exit 1 ;;
esac
EOF

cat > "$MOCK_BIN/scutil" <<'EOF'
#!/usr/bin/env bash
printf 'Maldoria\n'
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/defaults" "$MOCK_BIN/scutil"

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >/dev/null

assert_contains "$STATE_DIR/com.googlecode.iterm2.AllowClipboardAccess" 'true' 'iterm2 setting written'
LOG_FILE="$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers/Maldoria Installations and Configurations-$(date '+%Y%m%d')---------.csv"
assert_contains "$LOG_FILE" 'iTerm2 AllowClipboardAccess' 'iterm2 change is logged'

echo "iTerm2 runtime checks passed"
