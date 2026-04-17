#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/caddy-configure"
HELPERS="$ROOT/tests/lib/runtime-helpers.sh"
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"
STATE_DIR="$TMPDIR/state"
BREW_PREFIX="$TMPDIR/homebrew"
HOST_PYTHON3="$(command -v python3)"
mkdir -p "$MOCK_BIN" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$STATE_DIR" "$BREW_PREFIX/etc"
trap 'rm -rf "$TMPDIR"' EXIT
source "$HELPERS"

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
cat > "$MOCK_BIN/python3" <<EOF
#!/usr/bin/env bash
exec "$HOST_PYTHON3" "\$@"
EOF
cat > "$MOCK_BIN/brew" <<EOF
#!/usr/bin/env bash
case "\$1" in
  shellenv) ;;
  --prefix) printf '%s\n' "$BREW_PREFIX" ;;
  *) exit 0 ;;
esac
EOF
cat > "$MOCK_BIN/caddy" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == validate ]]; then
  printf '%s\n' "$*" >> "$STATE_DIR/caddy.log"
  exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/scutil" "$MOCK_BIN/xcode-select" "$MOCK_BIN/python3" "$MOCK_BIN/brew" "$MOCK_BIN/caddy"

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >/dev/null

TARGET_CONFIG="$BREW_PREFIX/etc/Caddyfile"
assert_contains "$TARGET_CONFIG" 'https://127.0.0.1:8123 {' 'shared Caddy HTTPS fragment is deployed'
assert_contains "$TARGET_CONFIG" 'reverse_proxy https://hovaryn.mioverso.com:8123' 'managed Caddy reverse proxy is deployed'
assert_contains "$STATE_DIR/caddy.log" 'validate --config' 'managed shared Caddyfile is validated before deployment'

COUNT_BEFORE=$("$HOST_PYTHON3" - "$STATE_DIR/caddy.log" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).read_text().count('validate --config'))
PY
)
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >/dev/null
COUNT_AFTER=$("$HOST_PYTHON3" - "$STATE_DIR/caddy.log" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).read_text().count('validate --config'))
PY
)
if [[ "$COUNT_AFTER" -le "$COUNT_BEFORE" ]]; then
  printf 'assertion failed: caddy-configure should still validate on rerun\n' >&2
  exit 1
fi

cat > "$MOCK_BIN/caddy" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == validate ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "$MOCK_BIN/caddy"
PREV_CONTENT="$(cat "$TARGET_CONFIG")"
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >"$STATE_DIR/out" 2>"$STATE_DIR/err"; then
  printf 'assertion failed: caddy-configure should fail when validation fails\n' >&2
  exit 1
fi
if [[ "$(cat "$TARGET_CONFIG")" != "$PREV_CONTENT" ]]; then
  printf 'assertion failed: validation failure should not rewrite the deployed Caddyfile\n' >&2
  exit 1
fi

FRESH_PREFIX="$TMPDIR/fresh-prefix"
mkdir -p "$FRESH_PREFIX"
cat > "$MOCK_BIN/brew" <<EOF
#!/usr/bin/env bash
case "\$1" in
  shellenv) ;;
  --prefix) printf '%s\n' "$FRESH_PREFIX" ;;
  *) exit 0 ;;
esac
EOF
cat > "$MOCK_BIN/caddy" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == validate ]]; then
  exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN/brew" "$MOCK_BIN/caddy"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >/dev/null
assert_contains "$FRESH_PREFIX/etc/Caddyfile" 'https://127.0.0.1:8123 {' 'first-run custom prefix without pre-created etc still deploys the managed Caddyfile'

echo "Caddy runtime checks passed"
