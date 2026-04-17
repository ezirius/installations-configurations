#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
mkdir -p "$REPO_DIR/scripts/brew/macos" "$REPO_DIR/lib/shell" "$REPO_DIR/lib/shell/shared" "$REPO_DIR/config/repo/shared" "$REPO_DIR/config/brew/macos" "$TMPDIR/state"
trap 'rm -rf "$TMPDIR"' EXIT

cp "$ROOT/scripts/brew/macos/brew-bootstrap" "$REPO_DIR/scripts/brew/macos/brew-bootstrap"
cp "$ROOT/lib/shell/shared/common.sh" "$REPO_DIR/lib/shell/shared/common.sh"
cp "$ROOT/config/repo/shared/repo-settings-shared.conf" "$REPO_DIR/config/repo/shared/repo-settings-shared.conf"
cp "$ROOT/config/brew/macos/brew-settings-shared.conf" "$REPO_DIR/config/brew/macos/brew-settings-shared.conf"

cat > "$REPO_DIR/scripts/brew/macos/brew-install" <<'EOF'
#!/usr/bin/env bash
printf 'brew-install\n' >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
cat > "$REPO_DIR/scripts/brew/macos/brew-upgrade" <<'EOF'
#!/usr/bin/env bash
printf 'brew-upgrade\n' >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
cat > "$REPO_DIR/scripts/brew/macos/brew-configure" <<'EOF'
#!/usr/bin/env bash
printf 'brew-configure\n' >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
cat > "$REPO_DIR/scripts/brew/macos/brew-service" <<'EOF'
#!/usr/bin/env bash
printf 'brew-service %s\n' "$1" >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
chmod +x "$REPO_DIR/scripts/brew/macos"/*

cat > "$TMPDIR/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
chmod +x "$TMPDIR/uname"

LOG_FILE="$TMPDIR/state/bootstrap.log"
PATH="$TMPDIR:$PATH" BOOTSTRAP_RUNTIME_LOG="$LOG_FILE" "$REPO_DIR/scripts/brew/macos/brew-bootstrap" >/dev/null

EXPECTED=$'brew-install\nbrew-upgrade\nbrew-configure\nbrew-service start'
ACTUAL="$(cat "$LOG_FILE")"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  printf 'assertion failed: brew-bootstrap runtime order\nexpected:\n%s\nactual:\n%s\n' "$EXPECTED" "$ACTUAL" >&2
  exit 1
fi

echo "Brew bootstrap runtime checks passed"
