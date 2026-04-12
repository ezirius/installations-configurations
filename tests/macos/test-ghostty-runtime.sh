#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/ghostty-configure"
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"
mkdir -p "$MOCK_BIN" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$HOME_DIR/.config"
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

cat > "$MOCK_BIN/scutil" <<'EOF'
#!/usr/bin/env bash
printf 'Maldoria\n'
EOF

cat > "$MOCK_BIN/xcode-select" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -p ]]
printf '/Library/Developer/CommandLineTools\n'
EOF

cat > "$MOCK_BIN/brew" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  shellenv) ;;
  --prefix) printf '/opt/homebrew\n' ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/scutil" "$MOCK_BIN/xcode-select" "$MOCK_BIN/brew"

mkdir -p "$HOME_DIR/.config/ghostty"
cat > "$HOME_DIR/.config/ghostty/config.ghostty" <<'EOF'
old-config = true
EOF
mkdir -p /opt/homebrew/bin
touch /opt/homebrew/bin/nu
chmod +x /opt/homebrew/bin/nu

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" "$SCRIPT_FILE" >/dev/null

TARGET_CONFIG="$HOME_DIR/.config/ghostty/config.ghostty"
TARGET_INCLUDE="$HOME_DIR/.config/ghostty/installations-configurations.ghostty"
assert_contains "$TARGET_CONFIG" 'old-config = true' 'existing primary ghostty config is preserved'
assert_contains "$TARGET_CONFIG" 'config-file = "installations-configurations.ghostty"' 'managed include is wired into primary ghostty config'
assert_contains "$TARGET_INCLUDE" 'command = /opt/homebrew/bin/nu' 'ghostty command uses absolute nu path'
assert_contains "$TARGET_INCLUDE" 'background = 1a1b26' 'ghostty dark theme is deployed'
LOG_FILE="$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers/Maldoria Installations and Configurations-$(date '+%Y%m%d')---------.csv"
assert_contains "$LOG_FILE" 'Ghostty config' 'ghostty config deployment is logged'
assert_contains "$LOG_FILE" 'Ghostty config include' 'ghostty primary config wiring is logged'

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" "$SCRIPT_FILE" >/dev/null
INCLUDE_COUNT=$(python3 - "$TARGET_CONFIG" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).read_text().count('config-file = "installations-configurations.ghostty"'))
PY
)
if [[ "$INCLUDE_COUNT" != "1" ]]; then
  printf 'assertion failed: ghostty-configure should not append duplicate include directives\n' >&2
  exit 1
fi

cat > "$MOCK_BIN/brew" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  shellenv) ;;
  --prefix) printf '/usr/local\n' ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$MOCK_BIN/brew"
mkdir -p /usr/local/bin
touch /usr/local/bin/nu
chmod +x /usr/local/bin/nu
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" "$SCRIPT_FILE" >/dev/null
assert_contains "$TARGET_INCLUDE" 'command = /usr/local/bin/nu' 'ghostty-configure updates the include when the rendered shell path changes'

rm -f /usr/local/bin/nu
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" "$SCRIPT_FILE" >"$TMPDIR/out" 2>"$TMPDIR/err"; then
  printf 'assertion failed: ghostty-configure should fail when the resolved Homebrew nu path is missing\n' >&2
  exit 1
fi
assert_contains "$TMPDIR/err" 'nushell is not installed at /usr/local/bin/nu' 'ghostty-configure reports a missing absolute nu path clearly'

echo "Ghostty runtime checks passed"
