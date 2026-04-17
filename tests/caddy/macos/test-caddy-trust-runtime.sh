#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/caddy/macos/caddy-trust"
HELPERS="$ROOT/tests/shared/shared/runtime-helpers.sh"
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
HOME_DIR="$TMPDIR/home"
BREW_PREFIX="$TMPDIR/homebrew"
mkdir -p "$MOCK_BIN" "$STATE_DIR" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$HOME_DIR/Library/Keychains" "$BREW_PREFIX/etc"
trap 'rm -rf "$TMPDIR"' EXIT
source "$HELPERS"

cp "$ROOT/config/caddy/macos/caddy-runtime-shared.Caddyfile" "$BREW_PREFIX/etc/Caddyfile"

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

FAIL_DIR="$TMPDIR/fail-trust"
mkdir -p "$FAIL_DIR/bin" "$FAIL_DIR/state" "$FAIL_DIR/home/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$FAIL_DIR/home/Library/Keychains" "$FAIL_DIR/homebrew/etc"
cp "$ROOT/config/caddy/macos/caddy-runtime-shared.Caddyfile" "$FAIL_DIR/homebrew/etc/Caddyfile"
cp "$MOCK_BIN/uname" "$FAIL_DIR/bin/uname"
cp "$MOCK_BIN/scutil" "$FAIL_DIR/bin/scutil"
cp "$MOCK_BIN/xcode-select" "$FAIL_DIR/bin/xcode-select"
cat > "$FAIL_DIR/bin/brew" <<EOF
#!/usr/bin/env bash
case "\$1" in
  shellenv) ;;
  --prefix) printf '%s\n' "$FAIL_DIR/homebrew" ;;
  *) exit 0 ;;
esac
EOF
cat > "$FAIL_DIR/bin/security" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == find-certificate ]]; then
  exit 1
fi
exit 0
EOF
cat > "$FAIL_DIR/bin/caddy" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == trust ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "$FAIL_DIR/bin/brew" "$FAIL_DIR/bin/security" "$FAIL_DIR/bin/caddy"
if PATH="$FAIL_DIR/bin:$PATH" HOME="$FAIL_DIR/home" "$SCRIPT_FILE" >"$FAIL_DIR/out" 2>"$FAIL_DIR/err"; then
  printf 'assertion failed: caddy-trust should fail when caddy trust itself fails\n' >&2
  exit 1
fi

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" >/dev/null

assert_contains "$STATE_DIR/caddy.log" 'trust --config' 'caddy trust uses the managed Caddyfile path'

COUNT_BEFORE=$(grep -o 'trust --config' "$STATE_DIR/caddy.log" | wc -l | tr -d ' ')
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" >/dev/null
COUNT_AFTER=$(grep -o 'trust --config' "$STATE_DIR/caddy.log" | wc -l | tr -d ' ')
if [[ "$COUNT_AFTER" -le "$COUNT_BEFORE" ]]; then
  printf 'assertion failed: caddy-trust should re-run caddy trust to avoid stale certificate-name false positives\n' >&2
  exit 1
fi

STALE_DIR="$TMPDIR/stale-name"
mkdir -p "$STALE_DIR/bin" "$STALE_DIR/state" "$STALE_DIR/home/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$STALE_DIR/home/Library/Keychains" "$STALE_DIR/homebrew/etc"
cp "$ROOT/config/caddy/macos/caddy-runtime-shared.Caddyfile" "$STALE_DIR/homebrew/etc/Caddyfile"
cp "$MOCK_BIN/uname" "$STALE_DIR/bin/uname"
cp "$MOCK_BIN/scutil" "$STALE_DIR/bin/scutil"
cp "$MOCK_BIN/xcode-select" "$STALE_DIR/bin/xcode-select"
cat > "$STALE_DIR/bin/brew" <<EOF
#!/usr/bin/env bash
case "\$1" in
  shellenv) ;;
  --prefix) printf '%s\n' "$STALE_DIR/homebrew" ;;
  *) exit 0 ;;
esac
EOF
cat > "$STALE_DIR/bin/security" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == find-certificate ]]; then
  exit 0
fi
exit 0
EOF
cat > "$STALE_DIR/bin/caddy" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == trust ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "$STALE_DIR/bin/brew" "$STALE_DIR/bin/security" "$STALE_DIR/bin/caddy"
if PATH="$STALE_DIR/bin:$PATH" HOME="$STALE_DIR/home" "$SCRIPT_FILE" >"$STALE_DIR/out" 2>"$STALE_DIR/err"; then
  printf 'assertion failed: caddy-trust should not treat a stale certificate name as sufficient trust state\n' >&2
  exit 1
fi

BROKEN_DIR="$TMPDIR/broken"
mkdir -p "$BROKEN_DIR/bin" "$BROKEN_DIR/state" "$BROKEN_DIR/home/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$BROKEN_DIR/home/Library/Keychains" "$BROKEN_DIR/homebrew/etc"
cp "$ROOT/config/caddy/macos/caddy-runtime-shared.Caddyfile" "$BROKEN_DIR/homebrew/etc/Caddyfile"
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
