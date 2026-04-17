#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/caddy-service"
HELPERS="$ROOT/lib/test/runtime-helpers.sh"
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
HOME_DIR="$TMPDIR/home"
BREW_PREFIX="$TMPDIR/homebrew"
mkdir -p "$MOCK_BIN" "$STATE_DIR" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$BREW_PREFIX/etc"
trap 'rm -rf "$TMPDIR"' EXIT
source "$HELPERS"

cp "$ROOT/config/caddy/shared-macos.Caddyfile" "$BREW_PREFIX/etc/Caddyfile"

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
cat > "$MOCK_BIN/lsof" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/xcode-select" "$MOCK_BIN/brew" "$MOCK_BIN/caddy" "$MOCK_BIN/lsof"

MISSING_DIR="$TMPDIR/missing"
mkdir -p "$MISSING_DIR/bin" "$MISSING_DIR/state" "$MISSING_DIR/home/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$MISSING_DIR/homebrew/etc"
cp "$MOCK_BIN/uname" "$MISSING_DIR/bin/uname"
cp "$MOCK_BIN/xcode-select" "$MISSING_DIR/bin/xcode-select"
cp "$MOCK_BIN/caddy" "$MISSING_DIR/bin/caddy"
cat > "$MISSING_DIR/bin/brew" <<EOF
#!/usr/bin/env bash
case "\$1" in
  shellenv) ;;
  --prefix) printf '%s\n' "$MISSING_DIR/homebrew" ;;
  services)
    if [[ "\${2:-}" == list ]]; then
      printf 'caddy none user %s/Caddy.plist\n' "$MISSING_DIR/homebrew"
      exit 0
    fi
    shift
    printf '%s\n' "services \$*" >> "$MISSING_DIR/state/brew.log"
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$MISSING_DIR/bin"/*
if PATH="$MISSING_DIR/bin:$PATH" HOME="$MISSING_DIR/home" "$SCRIPT_FILE" start >"$MISSING_DIR/out" 2>"$MISSING_DIR/err"; then
  printf 'assertion failed: caddy-service should fail when the managed Caddyfile is missing\n' >&2
  exit 1
fi
assert_contains "$MISSING_DIR/err" 'Managed Caddyfile not found' 'caddy-service reports missing deployed config clearly'

cat > "$MOCK_BIN/caddy" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$STATE_DIR/caddy.log"
if [[ "\$1" == validate ]]; then
  exit 1
fi
EOF
chmod +x "$MOCK_BIN/caddy"
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" start >"$STATE_DIR/invalid.out" 2>"$STATE_DIR/invalid.err"; then
  printf 'assertion failed: caddy-service should fail when runtime config validation fails\n' >&2
  exit 1
fi

if ! PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" status >"$STATE_DIR/invalid-status.out" 2>"$STATE_DIR/invalid-status.err"; then
  printf 'assertion failed: caddy-service status should work when runtime config validation fails\n' >&2
  exit 1
fi

if ! PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" stop >"$STATE_DIR/invalid-stop.out" 2>"$STATE_DIR/invalid-stop.err"; then
  printf 'assertion failed: caddy-service stop should work when runtime config validation fails\n' >&2
  exit 1
fi

assert_contains "$STATE_DIR/brew.log" 'services info caddy' 'caddy-service status still works when validation fails'
assert_contains "$STATE_DIR/brew.log" 'services stop caddy' 'caddy-service stop still works when validation fails'

cat > "$MOCK_BIN/caddy" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$STATE_DIR/caddy.log"
EOF
chmod +x "$MOCK_BIN/caddy"
: > "$STATE_DIR/caddy.log"

if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" reload >"$STATE_DIR/reload.out" 2>"$STATE_DIR/reload.err"; then
  printf 'assertion failed: caddy-service reload should fail when the service is not running\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/reload.err" 'Caddy service is not running' 'reload reports a clear error when the service is stopped'
assert_contains "$STATE_DIR/caddy.log" 'validate --config' 'caddy-service validates the runtime config before managing the service'

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
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" stop >/dev/null
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" restart >/dev/null

assert_contains "$STATE_DIR/brew.log" 'services start caddy' 'caddy service starts through brew services'
assert_contains "$STATE_DIR/brew.log" 'services stop caddy' 'caddy service stop uses brew services stop'
assert_contains "$STATE_DIR/brew.log" 'services restart caddy' 'caddy service restart uses brew services restart'
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

cat > "$MOCK_BIN/lsof" <<'EOF'
#!/usr/bin/env bash
exit 0
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
chmod +x "$MOCK_BIN/lsof"
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" start >"$STATE_DIR/port.out" 2>"$STATE_DIR/port.err"; then
  printf 'assertion failed: caddy-service start should fail when the configured listener port is already in use\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/port.err" 'listener port is already in use' 'caddy-service reports listener port conflicts clearly'

cat > "$BREW_PREFIX/etc/Caddyfile" <<'EOF'
{
  servers {
    metrics
  }
}

  :8443 {
  respond "ok"
}
EOF
: > "$STATE_DIR/brew.log"
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" start >"$STATE_DIR/global-port.out" 2>"$STATE_DIR/global-port.err"; then
  printf 'assertion failed: caddy-service start should fail when a leading global options block still uses a conflicting listener port\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/global-port.err" 'listener port is already in use' 'caddy-service detects listener port conflicts when the Caddyfile starts with global options'
assert_not_contains "$STATE_DIR/brew.log" 'services start caddy' 'caddy-service should not try to start brew services when a global-options Caddyfile has a conflicting listener port'

cat > "$MOCK_BIN/lsof" <<'EOF'
#!/usr/bin/env bash
exit 1
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
    if [[ "\$*" == 'start caddy' ]]; then
      exit 1
    fi
    printf '%s\n' "services \$*" >> "$STATE_DIR/brew.log"
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$MOCK_BIN/lsof" "$MOCK_BIN/brew"
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" start >/dev/null 2>"$STATE_DIR/start-fail.err"; then
  printf 'assertion failed: caddy-service start should fail when brew services start fails\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/start-fail.err" 'failed to start' 'caddy-service reports start failures clearly'

echo "Caddy service runtime checks passed"
