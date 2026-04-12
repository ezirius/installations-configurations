#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/caddy-trust"
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
HOME_DIR="$TMPDIR/home"
BREW_PREFIX="$TMPDIR/homebrew"
mkdir -p "$MOCK_BIN" "$STATE_DIR" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$HOME_DIR/Library/Keychains" "$BREW_PREFIX/etc"
trap 'rm -rf "$TMPDIR"' EXIT

assert_contains() {
  local file="$1" needle="$2" message="$3"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nmissing: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

cp "$ROOT/config/caddy/shared.Caddyfile" "$BREW_PREFIX/etc/Caddyfile"

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

cat > "$MOCK_BIN/brew" <<EOF
#!/usr/bin/env bash
case "\$1" in
  shellenv) ;;
  --prefix) printf '%s\n' "$BREW_PREFIX" ;;
  *) exit 0 ;;
esac
EOF

cat > "$MOCK_BIN/security" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == find-certificate ]]; then
  if [[ -f "$STATE_DIR/trusted.flag" ]]; then
    exit 0
  fi
  exit 1
fi
exit 0
EOF

cat > "$MOCK_BIN/caddy" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == trust ]]; then
  touch "$STATE_DIR/trusted.flag"
  printf '%s\n' "\$*" >> "$STATE_DIR/caddy.log"
  exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/scutil" "$MOCK_BIN/xcode-select" "$MOCK_BIN/brew" "$MOCK_BIN/security" "$MOCK_BIN/caddy"

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" >/dev/null

assert_contains "$STATE_DIR/caddy.log" 'trust --config' 'caddy trust uses the managed Caddyfile path'
LOG_FILE="$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers/Maldoria Installations and Configurations-$(date '+%Y%m%d')---------.csv"
assert_contains "$LOG_FILE" 'Caddy local CA' 'caddy trust is logged when trust is added'

COUNT_BEFORE=$(python3 - "$STATE_DIR/caddy.log" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).read_text().count('trust --config'))
PY
)
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" >/dev/null
COUNT_AFTER=$(python3 - "$STATE_DIR/caddy.log" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).read_text().count('trust --config'))
PY
)
if [[ "$COUNT_BEFORE" != "$COUNT_AFTER" ]]; then
  printf 'assertion failed: caddy-trust should not call caddy trust again when already trusted\n' >&2
  exit 1
fi

BROKEN_DIR="$TMPDIR/broken"
mkdir -p "$BROKEN_DIR/bin" "$BROKEN_DIR/state" "$BROKEN_DIR/home/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$BROKEN_DIR/home/Library/Keychains" "$BROKEN_DIR/homebrew/etc"
cp "$ROOT/config/caddy/shared.Caddyfile" "$BROKEN_DIR/homebrew/etc/Caddyfile"
cp "$MOCK_BIN/uname" "$BROKEN_DIR/bin/uname"
cp "$MOCK_BIN/scutil" "$BROKEN_DIR/bin/scutil"
cp "$MOCK_BIN/xcode-select" "$BROKEN_DIR/bin/xcode-select"
cat > "$BROKEN_DIR/bin/brew" <<EOF
#!/usr/bin/env bash
case "\$1" in
  shellenv) ;;
  --prefix) printf '%s\n' "$BROKEN_DIR/homebrew" ;;
  *) exit 0 ;;
esac
EOF
cat > "$BROKEN_DIR/bin/security" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == find-certificate ]]; then
  exit 1
fi
exit 0
EOF
cat > "$BROKEN_DIR/bin/caddy" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == trust ]]; then
  exit 0
fi
exit 0
EOF
chmod +x "$BROKEN_DIR/bin/brew" "$BROKEN_DIR/bin/security" "$BROKEN_DIR/bin/caddy"
if PATH="$BROKEN_DIR/bin:$PATH" HOME="$BROKEN_DIR/home" "$SCRIPT_FILE" >"$BROKEN_DIR/out" 2>"$BROKEN_DIR/err"; then
  printf 'assertion failed: caddy-trust should fail when trust is not detectable afterwards\n' >&2
  exit 1
fi
assert_contains "$BROKEN_DIR/err" 'without a detectable trusted local CA certificate' 'caddy-trust fails if trust is not detectable afterwards'

echo "Caddy trust runtime checks passed"
