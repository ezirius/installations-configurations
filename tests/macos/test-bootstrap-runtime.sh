#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
mkdir -p "$REPO_DIR/scripts/macos" "$REPO_DIR/lib/shell" "$TMPDIR/state"
trap 'rm -rf "$TMPDIR"' EXIT

cp "$ROOT/scripts/macos/bootstrap" "$REPO_DIR/scripts/macos/bootstrap"
cp "$ROOT/lib/shell/common.sh" "$REPO_DIR/lib/shell/common.sh"

cat > "$REPO_DIR/scripts/macos/brew-install" <<'EOF'
#!/usr/bin/env bash
printf 'brew-install\n' >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
cat > "$REPO_DIR/scripts/macos/brewfile-install" <<'EOF'
#!/usr/bin/env bash
printf 'brewfile-install\n' >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
cat > "$REPO_DIR/scripts/macos/brew-upgrade" <<'EOF'
#!/usr/bin/env bash
printf 'brew-upgrade\n' >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
cat > "$REPO_DIR/scripts/macos/caddy-configure" <<'EOF'
#!/usr/bin/env bash
printf 'caddy-configure\n' >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
cat > "$REPO_DIR/scripts/macos/caddy-service" <<'EOF'
#!/usr/bin/env bash
printf 'caddy-service %s\n' "$1" >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
cat > "$REPO_DIR/scripts/macos/caddy-trust" <<'EOF'
#!/usr/bin/env bash
printf 'caddy-trust\n' >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
cat > "$REPO_DIR/scripts/macos/ghostty-configure" <<'EOF'
#!/usr/bin/env bash
printf 'ghostty-configure\n' >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
cat > "$REPO_DIR/scripts/macos/jj-configure" <<'EOF'
#!/usr/bin/env bash
printf 'jj-configure\n' >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
cat > "$REPO_DIR/scripts/macos/nushell-configure" <<'EOF'
#!/usr/bin/env bash
printf 'nushell-configure\n' >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
cat > "$REPO_DIR/scripts/macos/devtools-configure" <<'EOF'
#!/usr/bin/env bash
printf 'devtools-configure\n' >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
cat > "$REPO_DIR/scripts/macos/system-configure" <<'EOF'
#!/usr/bin/env bash
printf 'system-configure\n' >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
cat > "$REPO_DIR/scripts/macos/podman-machine-install" <<'EOF'
#!/usr/bin/env bash
printf 'podman-machine-install\n' >> "$BOOTSTRAP_RUNTIME_LOG"
EOF
chmod +x "$REPO_DIR/scripts/macos"/*

cat > "$TMPDIR/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
chmod +x "$TMPDIR/uname"

LOG_FILE="$TMPDIR/state/bootstrap.log"
PATH="$TMPDIR:$PATH" BOOTSTRAP_RUNTIME_LOG="$LOG_FILE" "$REPO_DIR/scripts/macos/bootstrap" >/dev/null

EXPECTED=$'brew-install\nbrewfile-install\nbrew-upgrade\ncaddy-configure\ncaddy-service start\ncaddy-trust\nghostty-configure\njj-configure\nnushell-configure\ndevtools-configure\nsystem-configure\npodman-machine-install'
ACTUAL="$(cat "$LOG_FILE")"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  printf 'assertion failed: bootstrap runtime order\nexpected:\n%s\nactual:\n%s\n' "$EXPECTED" "$ACTUAL" >&2
  exit 1
fi

echo "Bootstrap runtime checks passed"
