#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/caddy/macos/caddy-configure"
HELPERS="$ROOT/tests/shared/shared/runtime-helpers.sh"
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"
STATE_DIR="$TMPDIR/state"
BREW_PREFIX="$TMPDIR/homebrew"
OVERRIDE_FILE="$TMPDIR/override.Caddyfile"
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

cat > "$OVERRIDE_FILE" <<'EOF'
127.0.0.1:8123 {
    respond "override"
}
EOF

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$OVERRIDE_FILE" >/dev/null
TARGET_CONFIG="$BREW_PREFIX/etc/Caddyfile"
cmp "$OVERRIDE_FILE" "$TARGET_CONFIG"
assert_contains "$STATE_DIR/caddy.log" 'validate --config' 'override Caddyfile is validated before deployment'

if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$TMPDIR/missing.Caddyfile" >/dev/null 2>"$STATE_DIR/missing.err"; then
  printf 'assertion failed: caddy-configure should fail when an explicit override path is missing\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/missing.err" 'Caddyfile not found' 'caddy-configure reports missing override files clearly'

echo "Caddy override runtime checks passed"
