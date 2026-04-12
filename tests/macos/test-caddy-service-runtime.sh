#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/caddy-service"
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
HOME_DIR="$TMPDIR/home"
BREW_PREFIX="$TMPDIR/homebrew"
mkdir -p "$MOCK_BIN" "$STATE_DIR" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$BREW_PREFIX/etc"
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
  services)
    if [[ "\${2:-}" == list ]]; then
      printf 'caddy none user %s/Caddy.plist\n' "$BREW_PREFIX"
      exit 0
    fi
    shift
    printf '%s\n' "services \$*" >> "$STATE_DIR/brew.log"
    ;;
  *) exit 0 ;;
esac
EOF

cat > "$MOCK_BIN/caddy" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$STATE_DIR/caddy.log"
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/xcode-select" "$MOCK_BIN/brew" "$MOCK_BIN/caddy"

if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" reload >"$STATE_DIR/reload.out" 2>"$STATE_DIR/reload.err"; then
  printf 'assertion failed: caddy-service reload should fail when the service is not running\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/reload.err" 'Caddy service is not running' 'reload reports a clear error when the service is stopped'

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" start >/dev/null

cat > "$MOCK_BIN/brew" <<EOF
#!/usr/bin/env bash
case "\$1" in
  shellenv) ;;
  --prefix) printf '%s\n' "$BREW_PREFIX" ;;
  services)
    if [[ "\${2:-}" == list ]]; then
      printf 'caddy started user %s/Caddy.plist\n' "$BREW_PREFIX"
      exit 0
    fi
    if [[ "\$1" == services ]]; then
      shift
      printf '%s\n' "services \$*" >> "$STATE_DIR/brew.log"
    else
      exit 0
    fi
    ;;
esac
EOF
chmod +x "$MOCK_BIN/brew"

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" reload >/dev/null
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" status >/dev/null
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" start >/dev/null

assert_contains "$STATE_DIR/brew.log" 'services start caddy' 'caddy service starts through brew services'
assert_contains "$STATE_DIR/brew.log" 'services info caddy' 'caddy service status uses brew services info'
assert_contains "$STATE_DIR/caddy.log" 'reload --config' 'caddy reload uses managed config path'
START_COUNT=$(python3 - "$STATE_DIR/brew.log" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).read_text().count('services start caddy'))
PY
)
if [[ "$START_COUNT" != "1" ]]; then
  printf 'assertion failed: caddy-service start should call brew services start only once across the test\n' >&2
  exit 1
fi

echo "Caddy service runtime checks passed"
