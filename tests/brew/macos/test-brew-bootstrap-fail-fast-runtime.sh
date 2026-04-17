#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
mkdir -p "$REPO_DIR/scripts/brew/macos" "$REPO_DIR/scripts/caddy/macos" "$REPO_DIR/lib/shell" "$REPO_DIR/lib/shell/shared" "$REPO_DIR/config/repo/shared" "$REPO_DIR/config/brew/macos" "$TMPDIR/state"
trap 'rm -rf "$TMPDIR"' EXIT

cp "$ROOT/scripts/brew/macos/brew-bootstrap" "$REPO_DIR/scripts/brew/macos/brew-bootstrap"
cp "$ROOT/lib/shell/shared/common.sh" "$REPO_DIR/lib/shell/shared/common.sh"
cp "$ROOT/config/repo/shared/repo-settings-shared.conf" "$REPO_DIR/config/repo/shared/repo-settings-shared.conf"
cp "$ROOT/config/brew/macos/brew-settings-shared.conf" "$REPO_DIR/config/brew/macos/brew-settings-shared.conf"

for script_name in brew-install brew-configure brew-service; do
  cat > "$REPO_DIR/scripts/brew/macos/$script_name" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$script_name' >> "\$BOOTSTRAP_RUNTIME_LOG"
EOF
done

cat > "$REPO_DIR/scripts/brew/macos/brew-upgrade" <<'EOF'
#!/usr/bin/env bash
printf 'brew-upgrade\n' >> "$BOOTSTRAP_RUNTIME_LOG"
exit 1
EOF

cat > "$REPO_DIR/scripts/caddy/macos/caddy-service" <<'EOF'
#!/usr/bin/env bash
printf 'caddy-service %s\n' "$1" >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
chmod +x "$REPO_DIR/scripts/brew/macos"/*

cat > "$TMPDIR/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
chmod +x "$TMPDIR/uname"

LOG_FILE="$TMPDIR/state/bootstrap.log"
if PATH="$TMPDIR:$PATH" BOOTSTRAP_RUNTIME_LOG="$LOG_FILE" "$REPO_DIR/scripts/brew/macos/brew-bootstrap" >/dev/null 2>"$TMPDIR/err"; then
  printf 'assertion failed: brew-bootstrap should stop when a child step fails\n' >&2
  exit 1
fi

EXPECTED=$'brew-install\nbrew-upgrade'
ACTUAL="$(cat "$LOG_FILE")"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  printf 'assertion failed: brew-bootstrap fail-fast order\nexpected:\n%s\nactual:\n%s\n' "$EXPECTED" "$ACTUAL" >&2
  exit 1
fi

echo "Brew bootstrap fail-fast runtime checks passed"
