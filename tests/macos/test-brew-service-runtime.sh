#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPERS="$ROOT/tests/lib/runtime-helpers.sh"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
MOCK_BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
HOME_DIR="$TMPDIR/home"
SCRIPT_FILE="$REPO_DIR/scripts/macos/brew-service"
mkdir -p "$MOCK_BIN" "$STATE_DIR" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$REPO_DIR/scripts/macos" "$REPO_DIR/lib/shell" "$REPO_DIR/config/brew" "$REPO_DIR/config/repo" "$REPO_DIR/config/podman"
trap 'rm -rf "$TMPDIR"' EXIT
source "$HELPERS"

cp "$ROOT/scripts/macos/brew-service" "$REPO_DIR/scripts/macos/brew-service"
cp "$ROOT/lib/shell/common.sh" "$REPO_DIR/lib/shell/common.sh"
cp "$ROOT/config/repo/shared.conf" "$REPO_DIR/config/repo/shared.conf"
cp "$ROOT/config/podman/shared-macos.conf" "$REPO_DIR/config/podman/shared-macos.conf"

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

cat > "$REPO_DIR/config/brew/shared-macos.conf" <<'EOF'
BREW_CONFIGURE_STEPS=(
  "caddy-configure"
  "caddy-trust"
  "podman-configure"
)
BREW_BOOTSTRAP_STEPS=(
  "brew-install"
  "brew-upgrade"
  "brew-configure"
)
BREW_BOOTSTRAP_SERVICE_ACTION="start"
BREW_MANAGED_SERVICE_SCRIPTS=(
  "first-service"
  "second-service"
)
EOF

for step in first-service second-service; do
  cat > "$REPO_DIR/scripts/macos/$step" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' '$step' "\$1" >> "$STATE_DIR/services.log"
EOF
  chmod +x "$REPO_DIR/scripts/macos/$step"
done

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" restart >/dev/null
EXPECTED=$'first-service restart\nsecond-service restart'
ACTUAL="$(cat "$STATE_DIR/services.log")"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  printf 'assertion failed: brew-service should dispatch the selected action in config order\nexpected:\n%s\nactual:\n%s\n' "$EXPECTED" "$ACTUAL" >&2
  exit 1
fi

cat > "$REPO_DIR/scripts/macos/second-service" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' 'second-service' "\$1" >> "$STATE_DIR/fail.log"
exit 1
EOF
chmod +x "$REPO_DIR/scripts/macos/second-service"
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" start >/dev/null 2>"$STATE_DIR/fail.err"; then
  printf 'assertion failed: brew-service should fail when a managed service fails\n' >&2
  exit 1
fi

if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" invalid >/dev/null 2>"$STATE_DIR/invalid.err"; then
  printf 'assertion failed: brew-service should reject invalid actions\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/invalid.err" 'takes exactly 1 argument' 'brew-service reports invalid action usage clearly'

echo "Brew service runtime checks passed"
