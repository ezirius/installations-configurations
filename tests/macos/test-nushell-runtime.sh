#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/nushell-configure"
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"
STATE_DIR="$TMPDIR/state"
mkdir -p "$MOCK_BIN" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$HOME_DIR/.config" "$STATE_DIR"
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

cat > "$MOCK_BIN/atuin" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == init && "$2" == nu ]]
printf '# atuin init\n'
EOF

cat > "$MOCK_BIN/starship" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == init && "$2" == nu ]]
printf '# starship init\n'
EOF

cat > "$MOCK_BIN/zoxide" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == init && "$2" == nushell ]]
printf '# zoxide init\n'
EOF

cat > "$MOCK_BIN/jj" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == util && "$2" == completion && "$3" == nushell ]]
printf '# jj completion\n'
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/scutil" "$MOCK_BIN/xcode-select" "$MOCK_BIN/brew" "$MOCK_BIN/atuin" "$MOCK_BIN/starship" "$MOCK_BIN/zoxide" "$MOCK_BIN/jj"

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" NUSHELL_MACOS_COMPAT_PATH="$HOME_DIR/Library/Application Support/nushell" "$SCRIPT_FILE" >/dev/null

TARGET_DIR="$HOME_DIR/.config/nushell"
assert_contains "$TARGET_DIR/autoload/installations-configurations.nu" 'FZF_DEFAULT_OPTS' 'managed nushell autoload file sets fzf defaults'
assert_contains "$TARGET_DIR/atuin.nu" '# atuin init' 'atuin integration is generated'
assert_contains "$TARGET_DIR/starship.nu" '# starship init' 'starship integration is generated'
assert_contains "$TARGET_DIR/zoxide.nu" '# zoxide init' 'zoxide integration is generated'
assert_contains "$TARGET_DIR/completions-jj.nu" '# jj completion' 'jj completions are generated'
if [[ ! -L "$HOME_DIR/Library/Application Support/nushell" ]]; then
  printf 'assertion failed: Nushell compatibility path should be a symlink\n' >&2
  exit 1
fi
if [[ "$(readlink "$HOME_DIR/Library/Application Support/nushell")" != "$TARGET_DIR" ]]; then
  printf 'assertion failed: Nushell compatibility symlink target is wrong\n' >&2
  exit 1
fi
LOG_FILE="$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers/Maldoria Installations and Configurations-$(date '+%Y%m%d')---------.csv"
assert_contains "$LOG_FILE" 'Nushell compatibility symlink' 'nushell symlink deployment is logged'

COUNT_BEFORE=$(python3 - "$LOG_FILE" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).read_text().count('Nushell compatibility symlink'))
PY
)
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" NUSHELL_MACOS_COMPAT_PATH="$HOME_DIR/Library/Application Support/nushell" "$SCRIPT_FILE" >/dev/null
COUNT_AFTER=$(python3 - "$LOG_FILE" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).read_text().count('Nushell compatibility symlink'))
PY
)
if [[ "$COUNT_BEFORE" != "$COUNT_AFTER" ]]; then
  printf 'assertion failed: nushell-configure should not relog an already-correct compatibility symlink\n' >&2
  exit 1
fi

BROKEN_DIR="$TMPDIR/broken"
mkdir -p "$BROKEN_DIR/bin" "$BROKEN_DIR/home/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$BROKEN_DIR/home/.config" "$BROKEN_DIR/state" "$BROKEN_DIR/home/Library/Application Support/nushell"
cp "$MOCK_BIN/uname" "$BROKEN_DIR/bin/uname"
cp "$MOCK_BIN/scutil" "$BROKEN_DIR/bin/scutil"
cp "$MOCK_BIN/xcode-select" "$BROKEN_DIR/bin/xcode-select"
cp "$MOCK_BIN/brew" "$BROKEN_DIR/bin/brew"
cp "$MOCK_BIN/atuin" "$BROKEN_DIR/bin/atuin"
cp "$MOCK_BIN/starship" "$BROKEN_DIR/bin/starship"
cp "$MOCK_BIN/zoxide" "$BROKEN_DIR/bin/zoxide"
cp "$MOCK_BIN/jj" "$BROKEN_DIR/bin/jj"
chmod +x "$BROKEN_DIR/bin"/*
if PATH="$BROKEN_DIR/bin:$PATH" HOME="$BROKEN_DIR/home" XDG_CONFIG_HOME="$BROKEN_DIR/home/.config" NUSHELL_MACOS_COMPAT_PATH="$BROKEN_DIR/home/Library/Application Support/nushell" "$SCRIPT_FILE" >"$BROKEN_DIR/out" 2>"$BROKEN_DIR/err"; then
  printf 'assertion failed: nushell-configure should fail when the compatibility path exists as a real directory\n' >&2
  exit 1
fi
assert_contains "$BROKEN_DIR/err" 'already exists and is not a symlink' 'nushell-configure protects unmanaged compatibility paths'

echo "Nushell runtime checks passed"
