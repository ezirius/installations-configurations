#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
mkdir -p "$REPO_DIR/scripts/macos" "$REPO_DIR/lib/shell" "$TMPDIR/state"
trap 'rm -rf "$TMPDIR"' EXIT

cp "$ROOT/scripts/macos/bootstrap" "$REPO_DIR/scripts/macos/bootstrap"
cp "$ROOT/lib/shell/common.sh" "$REPO_DIR/lib/shell/common.sh"

for script_name in brew-install brewfile-install caddy-configure caddy-trust ghostty-configure jj-configure nushell-configure devtools-configure system-configure podman-machine-install; do
  cat > "$REPO_DIR/scripts/macos/$script_name" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$script_name' >> "\$BOOTSTRAP_RUNTIME_LOG"
EOF
done

cat > "$REPO_DIR/scripts/macos/brew-upgrade" <<'EOF'
#!/usr/bin/env bash
printf 'brew-upgrade\n' >> "$BOOTSTRAP_RUNTIME_LOG"
exit 1
EOF

cat > "$REPO_DIR/scripts/macos/caddy-service" <<'EOF'
#!/usr/bin/env bash
printf 'caddy-service %s\n' "$1" >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
chmod +x "$REPO_DIR/scripts/macos"/*

cat > "$TMPDIR/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
chmod +x "$TMPDIR/uname"

LOG_FILE="$TMPDIR/state/bootstrap.log"
if PATH="$TMPDIR:$PATH" BOOTSTRAP_RUNTIME_LOG="$LOG_FILE" "$REPO_DIR/scripts/macos/bootstrap" >/dev/null 2>"$TMPDIR/err"; then
  printf 'assertion failed: bootstrap should stop when a child step fails\n' >&2
  exit 1
fi

EXPECTED=$'brew-install\nbrewfile-install\nbrew-upgrade'
ACTUAL="$(cat "$LOG_FILE")"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  printf 'assertion failed: bootstrap fail-fast order\nexpected:\n%s\nactual:\n%s\n' "$EXPECTED" "$ACTUAL" >&2
  exit 1
fi

echo "Bootstrap fail-fast runtime checks passed"
