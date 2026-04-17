#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/podman/macos/podman-check"
HELPERS="$ROOT/tests/shared/shared/runtime-helpers.sh"
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
HOME_DIR="$TMPDIR/home"
HOST_RUNTIME="$ROOT/config/podman/macos/podman-runtime-settings-maldoria.conf"
mkdir -p "$MOCK_BIN" "$STATE_DIR" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers"
trap 'rm -rf "$TMPDIR"; rm -f "$HOST_RUNTIME"' EXIT
source "$HELPERS"

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
cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
exit 0
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/xcode-select" "$MOCK_BIN/scutil" "$MOCK_BIN/podman"

cat > "$HOST_RUNTIME" <<'EOF'
PODMAN_CHECK_IMAGE="docker.io/library/busybox:1.36"
EOF

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >"$STATE_DIR/out" 2>"$STATE_DIR/err"
EXPECTED=$'version\nmachine list\ninfo\nrun --rm docker.io/library/busybox:1.36 echo Hello from podman'
ACTUAL="$(cat "$STATE_DIR/podman.log")"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  printf 'assertion failed: podman-check should run the expected subcommands in order\nexpected:\n%s\nactual:\n%s\n' "$EXPECTED" "$ACTUAL" >&2
  exit 1
fi

rm -f "$HOST_RUNTIME"

rm -f "$MOCK_BIN/podman"
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" "$SCRIPT_FILE" >/dev/null 2>"$STATE_DIR/missing.err"; then
  printf 'assertion failed: podman-check should fail when podman is missing\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/missing.err" 'scripts/brew/macos/brew-bootstrap' 'podman-check reports the current bootstrap command clearly'

echo "Podman check runtime checks passed"
