#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMMON_FILE="$ROOT/lib/shell/common.sh"
TMPDIR="$(mktemp -d)"
HOST_PYTHON3="$(command -v python3)"
trap 'rm -rf "$TMPDIR"' EXIT

test -f "$COMMON_FILE"
grep -q 'safe_log_host_name' "$COMMON_FILE"
grep -q 'read_machine_config_value' "$COMMON_FILE"

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

cat > "$TMPDIR/bin/python3" <<EOF
#!/usr/bin/env bash
exec "$HOST_PYTHON3" "\$@"
EOF

chmod +x "$TMPDIR/bin/uname" "$TMPDIR/bin/scutil" "$TMPDIR/bin/hostname" "$TMPDIR/bin/python3"

PATH="$TMPDIR/bin:$PATH" ROOT="$ROOT" bash -c '
  source "$ROOT/lib/shell/common.sh"
  test "$(raw_host_name)" = "My Maldoria"
  test "$(normalize_name "My Maldoria.local!!")" = "my-maldoria-local"
  test "$(normalized_host_name)" = "my-maldoria"
  test "$(detect_log_host_name)" = "My Maldoria"
  test "$(shared_cross_platform_config_path "config/example" "conf")" = "$ROOT/config/example/shared-shared.conf"
  test "$(shared_platform_config_path "config/brew" "Brewfile")" = "$ROOT/config/brew/shared-macos.Brewfile"
  test "$(host_platform_config_path "config/brew" "Brewfile")" = "$ROOT/config/brew/my-maldoria-macos.Brewfile"
'

rm "$TMPDIR/bin/scutil"
PATH="$TMPDIR/bin:$PATH" ROOT="$ROOT" bash -c '
  source "$ROOT/lib/shell/common.sh"
  test "$(raw_host_name)" = "IgnoredHost"
  test "$(normalized_host_name)" = "ignoredhost"
  test "$(detect_log_host_name)" = "IgnoredHost"
'

cat > "$TMPDIR/bin/hostname" <<'EOF'
#!/usr/bin/env bash
printf 'Slash/Host\n'
EOF
chmod +x "$TMPDIR/bin/hostname"
PATH="$TMPDIR/bin:$PATH" ROOT="$ROOT" bash -c '
  source "$ROOT/lib/shell/common.sh"
  test "$(safe_log_host_name)" = "Slash-Host"
'

cat > "$TMPDIR/machine.conf" <<'EOF'
[machine]
token=100% literal
EOF

PATH="$TMPDIR/bin:$PATH" ROOT="$ROOT" bash -c '
  source "$ROOT/lib/shell/common.sh"
  test "$(read_machine_config_value "'$TMPDIR'/machine.conf" token)" = "100% literal"
'

echo "Common helper checks passed"
