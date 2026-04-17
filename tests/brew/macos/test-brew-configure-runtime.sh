#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HELPERS="$ROOT/tests/shared/shared/runtime-helpers.sh"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
MOCK_BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
HOME_DIR="$TMPDIR/home"
SCRIPT_FILE="$REPO_DIR/scripts/brew/macos/brew-configure"
mkdir -p "$MOCK_BIN" "$STATE_DIR" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$REPO_DIR/scripts/brew/macos" "$REPO_DIR/lib/shell" "$REPO_DIR/lib/shell/shared" "$REPO_DIR/config/brew/macos" "$REPO_DIR/config/repo/shared" "$REPO_DIR/config/podman/macos"
trap 'rm -rf "$TMPDIR"' EXIT
source "$HELPERS"

cp "$ROOT/scripts/brew/macos/brew-configure" "$REPO_DIR/scripts/brew/macos/brew-configure"
cp "$ROOT/lib/shell/shared/common.sh" "$REPO_DIR/lib/shell/shared/common.sh"
cp "$ROOT/config/repo/shared/repo-settings-shared.conf" "$REPO_DIR/config/repo/shared/repo-settings-shared.conf"
cp "$ROOT/config/podman/macos/podman-runtime-settings-shared.conf" "$REPO_DIR/config/podman/macos/podman-runtime-settings-shared.conf"

cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
cat > "$MOCK_BIN/xcode-select" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -p ]]
printf '/Library/Developer/CommandLineTools\n'
EOF
cat > "$MOCK_BIN/scutil" <<'EOF'
#!/usr/bin/env bash
printf 'Maldoria\n'
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/xcode-select" "$MOCK_BIN/scutil"

cat > "$REPO_DIR/config/brew/macos/brew-settings-shared.conf" <<'EOF'
BREW_CONFIGURE_STEPS=(
  "first-step"
  "second-step"
  "third-step"
)
BREW_BOOTSTRAP_STEPS=(
  "brew-install"
  "brew-upgrade"
  "brew-configure"
)
BREW_BOOTSTRAP_SERVICE_ACTION="start"
BREW_MANAGED_SERVICE_SCRIPTS=(
  "caddy-service"
)
EOF

for step in first-step second-step third-step; do
  cat > "$REPO_DIR/scripts/brew/macos/$step" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$step' >> "$STATE_DIR/steps.log"
EOF
  chmod +x "$REPO_DIR/scripts/brew/macos/$step"
done

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" >/dev/null
EXPECTED=$'first-step\nsecond-step\nthird-step'
ACTUAL="$(cat "$STATE_DIR/steps.log")"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  printf 'assertion failed: brew-configure should run configured steps in order\nexpected:\n%s\nactual:\n%s\n' "$EXPECTED" "$ACTUAL" >&2
  exit 1
fi

cat > "$REPO_DIR/scripts/brew/macos/second-step" <<EOF
#!/usr/bin/env bash
printf '%s\n' 'second-step' >> "$STATE_DIR/fail.log"
exit 1
EOF
chmod +x "$REPO_DIR/scripts/brew/macos/second-step"
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" >/dev/null 2>"$STATE_DIR/fail.err"; then
  printf 'assertion failed: brew-configure should fail when a configured step fails\n' >&2
  exit 1
fi
assert_not_contains "$STATE_DIR/fail.log" 'third-step' 'brew-configure stops before later steps after a failure'

echo "Brew configure runtime checks passed"
