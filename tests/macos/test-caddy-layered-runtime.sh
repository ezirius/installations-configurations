#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
STATE_DIR="$TMPDIR/state"
MOCK_BIN="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"
BREW_PREFIX="$TMPDIR/homebrew"
mkdir -p "$REPO_DIR/scripts/macos" "$REPO_DIR/lib/shell" "$REPO_DIR/config/caddy" "$STATE_DIR" "$MOCK_BIN" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$BREW_PREFIX/etc"
trap 'rm -rf "$TMPDIR"' EXIT

cp "$ROOT/scripts/macos/caddy-configure" "$REPO_DIR/scripts/macos/caddy-configure"
cp "$ROOT/lib/shell/common.sh" "$REPO_DIR/lib/shell/common.sh"

cat > "$REPO_DIR/config/caddy/shared.Caddyfile" <<'EOF'
127.0.0.1:9000 {
    respond "shared"
}
EOF
cat > "$REPO_DIR/config/caddy/maldoria.Caddyfile" <<'EOF'
127.0.0.1:9001 {
    respond "host"
}
EOF

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
cat > "$MOCK_BIN/python3" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/python3 "$@"
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

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$REPO_DIR/scripts/macos/caddy-configure" >/dev/null

TARGET_CONFIG="$BREW_PREFIX/etc/Caddyfile"
python3 - "$TARGET_CONFIG" <<'PY'
from pathlib import Path
import sys
data = Path(sys.argv[1]).read_text()
assert data.index('respond "shared"') < data.index('respond "host"')
assert data.count('respond "shared"') == 1
assert data.count('respond "host"') == 1
PY

PREV_CONTENT="$(cat "$TARGET_CONFIG")"
cat > "$MOCK_BIN/caddy" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == validate ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "$MOCK_BIN/caddy"
cat > "$REPO_DIR/config/caddy/maldoria.Caddyfile" <<'EOF'
127.0.0.1:9001 {
    respond "broken-host"
}
EOF
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$REPO_DIR/scripts/macos/caddy-configure" >"$STATE_DIR/out" 2>"$STATE_DIR/err"; then
  printf 'assertion failed: layered caddy-configure should fail when validation fails\n' >&2
  exit 1
fi
if [[ "$(cat "$TARGET_CONFIG")" != "$PREV_CONTENT" ]]; then
  printf 'assertion failed: failed layered validation should not rewrite the deployed Caddyfile\n' >&2
  exit 1
fi

echo "Caddy layered runtime checks passed"
