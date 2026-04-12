#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMMON_FILE="$ROOT/lib/shell/common.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

test -f "$COMMON_FILE"
grep -q '^platform_key() {$' "$COMMON_FILE"
grep -q '^normalize_name() {$' "$COMMON_FILE"
grep -q '^normalized_host_name() {$' "$COMMON_FILE"
grep -q '^shared_platform_config_path() {$' "$COMMON_FILE"
grep -q '^host_platform_config_path() {$' "$COMMON_FILE"
grep -q '^shared_host_config_path() {$' "$COMMON_FILE"
grep -q '^host_config_path() {$' "$COMMON_FILE"
grep -q '^preferred_python3_command() {$' "$COMMON_FILE"

mkdir -p "$TMPDIR/bin"

cat > "$TMPDIR/bin/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF

cat > "$TMPDIR/bin/scutil" <<'EOF'
#!/usr/bin/env bash
printf 'My Maldoria.local!!\n'
EOF

cat > "$TMPDIR/bin/hostname" <<'EOF'
#!/usr/bin/env bash
printf 'IgnoredHost\n'
EOF

cat > "$TMPDIR/bin/python3" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/python3 "$@"
EOF

chmod +x "$TMPDIR/bin/uname" "$TMPDIR/bin/scutil" "$TMPDIR/bin/hostname" "$TMPDIR/bin/python3"

PATH="$TMPDIR/bin:$PATH" ROOT="$ROOT" bash -c '
  source "$ROOT/lib/shell/common.sh"
  test "$(normalize_name "My Maldoria.local!!")" = "my-maldoria-local"
  test "$(normalized_host_name)" = "my-maldoria"
  test "$(shared_platform_config_path "config/brew" "Brewfile")" = "$ROOT/config/brew/shared-macos.Brewfile"
  test "$(host_platform_config_path "config/brew" "Brewfile")" = "$ROOT/config/brew/my-maldoria-macos.Brewfile"
  test "$(shared_host_config_path "config/caddy" "Caddyfile")" = "$ROOT/config/caddy/shared.Caddyfile"
  test "$(host_config_path "config/caddy" "Caddyfile")" = "$ROOT/config/caddy/my-maldoria.Caddyfile"
'

rm "$TMPDIR/bin/scutil"
PATH="$TMPDIR/bin:$PATH" ROOT="$ROOT" bash -c '
  source "$ROOT/lib/shell/common.sh"
  test "$(normalized_host_name)" = "ignoredhost"
'

echo "Common helper checks passed"
