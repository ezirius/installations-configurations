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
SHARED_RUNTIME="$ROOT/config/caddy/macos/caddy-runtime-shared.Caddyfile"
SHARED_SETTINGS="$ROOT/config/caddy/macos/caddy-settings-shared.conf"
HOST_SETTINGS="$ROOT/config/caddy/macos/caddy-settings-maldoria.conf"
HOST_RUNTIME="$ROOT/config/caddy/macos/caddy-runtime-maldoria.Caddyfile"
SHARED_RUNTIME_BACKUP="$TMPDIR/caddy-runtime-shared.Caddyfile"
SHARED_SETTINGS_BACKUP="$TMPDIR/caddy-settings-shared.conf"
mkdir -p "$MOCK_BIN" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$STATE_DIR" "$BREW_PREFIX/etc"
trap 'rm -f "$HOST_SETTINGS" "$HOST_RUNTIME"; if [[ -f "$SHARED_RUNTIME_BACKUP" ]]; then mv "$SHARED_RUNTIME_BACKUP" "$SHARED_RUNTIME"; fi; if [[ -f "$SHARED_SETTINGS_BACKUP" ]]; then mv "$SHARED_SETTINGS_BACKUP" "$SHARED_SETTINGS"; fi; rm -rf "$TMPDIR"' EXIT
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
mkdir -p "$BREW_PREFIX/bin"
cat > "$BREW_PREFIX/bin/python3" <<'EOF'
#!/usr/bin/env bash
output_path="$2"
shift 2
{
  first=1
  for source_path in "$@"; do
    if [[ "$first" != 1 ]]; then
      printf '\n\n'
    fi
    first=0
    perl -0pe 's/\s*\z/\n/' "$source_path"
  done
} > "$output_path"
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
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/scutil" "$MOCK_BIN/xcode-select" "$BREW_PREFIX/bin/python3" "$MOCK_BIN/brew" "$MOCK_BIN/caddy"

cat > "$HOST_SETTINGS" <<'EOF'
CADDY_RUNTIME_RELATIVE_PATH="etc/Caddy-layeredfile"
EOF
cat > "$HOST_RUNTIME" <<'EOF'
https://127.0.0.1:9443 {
    respond "layered host"
}
EOF

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >/dev/null

TARGET_CONFIG="$BREW_PREFIX/etc/Caddy-layeredfile"
assert_contains "$TARGET_CONFIG" 'https://127.0.0.1:8123 {' 'shared Caddy HTTPS fragment is deployed'
assert_contains "$TARGET_CONFIG" 'reverse_proxy https://hovaryn.mioverso.com:8123' 'managed Caddy reverse proxy is deployed'
assert_contains "$TARGET_CONFIG" 'https://127.0.0.1:9443 {' 'host-specific Caddy fragment is layered after the shared fragment'
assert_contains "$TARGET_CONFIG" 'respond "layered host"' 'host-specific Caddy content is deployed alongside the shared config'
assert_contains "$STATE_DIR/caddy.log" 'validate --config' 'managed shared Caddyfile is validated before deployment'

COUNT_BEFORE=$(grep -o 'validate --config' "$STATE_DIR/caddy.log" | wc -l | tr -d ' ')
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >/dev/null
COUNT_AFTER=$(grep -o 'validate --config' "$STATE_DIR/caddy.log" | wc -l | tr -d ' ')
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
if [[ -e "$TARGET_CONFIG.rendered" ]]; then
  printf 'assertion failed: validation failure should clean up the rendered Caddyfile staging path\n' >&2
  exit 1
fi

FRESH_PREFIX="$TMPDIR/fresh-prefix"
mkdir -p "$FRESH_PREFIX"
mkdir -p "$FRESH_PREFIX/bin"
cp "$BREW_PREFIX/bin/python3" "$FRESH_PREFIX/bin/python3"
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
assert_contains "$FRESH_PREFIX/etc/Caddy-layeredfile" 'https://127.0.0.1:8123 {' 'first-run custom prefix without pre-created etc still deploys the shared managed Caddyfile'
assert_contains "$FRESH_PREFIX/etc/Caddy-layeredfile" 'respond "layered host"' 'first-run custom prefix without pre-created etc also deploys matching host Caddy content'

rm -f "$HOST_SETTINGS" "$HOST_RUNTIME"

HOST_ONLY_PREFIX="$TMPDIR/host-only-prefix"
mkdir -p "$HOST_ONLY_PREFIX"
mkdir -p "$HOST_ONLY_PREFIX/bin"
cp "$BREW_PREFIX/bin/python3" "$HOST_ONLY_PREFIX/bin/python3"
cat > "$MOCK_BIN/brew" <<EOF
#!/usr/bin/env bash
case "\$1" in
  shellenv) ;;
  --prefix) printf '%s\n' "$HOST_ONLY_PREFIX" ;;
  *) exit 0 ;;
esac
EOF
cat > "$HOST_SETTINGS" <<'EOF'
CADDY_RUNTIME_RELATIVE_PATH="etc/Caddy-host-only"
EOF
cat > "$HOST_RUNTIME" <<'EOF'
https://127.0.0.1:9555 {
    respond "host only"
}
EOF
chmod +x "$MOCK_BIN/brew"
mv "$SHARED_RUNTIME" "$SHARED_RUNTIME_BACKUP"
mv "$SHARED_SETTINGS" "$SHARED_SETTINGS_BACKUP"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >/dev/null
assert_contains "$HOST_ONLY_PREFIX/etc/Caddy-host-only" 'respond "host only"' 'caddy-configure works when only a matching host-specific Caddyfile exists'

echo "Caddy runtime checks passed"
