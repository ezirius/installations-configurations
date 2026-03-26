#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/podman-machine-install"
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
HOME_DIR="$TMPDIR/home"
mkdir -p "$MOCK_BIN" "$STATE_DIR" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$HOME_DIR/.config/containers"
trap 'rm -rf "$TMPDIR"' EXIT

assert_contains() {
  local file="$1" needle="$2" message="$3"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nmissing: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

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

cat > "$MOCK_BIN/brew" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  shellenv) ;;
  --prefix) printf '/opt/homebrew\n' ;;
  *) exit 0 ;;
esac
EOF

cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
case "$1" in
  machine)
    case "$2" in
      inspect)
        if [[ -f "$STATE_DIR/machine.exists" ]]; then
          printf '{}\n'
          exit 0
        fi
        exit 1
        ;;
      init)
        : > "$STATE_DIR/machine.exists"
        ;;
      start|set)
        ;;
      *) exit 1 ;;
    esac
    ;;
  info)
    printf '{}\n'
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/scutil" "$MOCK_BIN/xcode-select" "$MOCK_BIN/brew" "$MOCK_BIN/podman"

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >/dev/null

test -f "$HOME_DIR/.config/containers/containers.conf"
cmp "$ROOT/config/containers/containers.conf" "$HOME_DIR/.config/containers/containers.conf"
assert_contains "$STATE_DIR/podman.log" 'machine init podman-machine-default' 'podman machine is initialised'
assert_contains "$STATE_DIR/podman.log" 'machine start podman-machine-default' 'podman machine is started'
LOG_FILE="$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers/Maldoria Installations and Configurations-$(date '+%Y%m%d')---------.csv"
assert_contains "$LOG_FILE" 'Podman machine' 'podman machine creation is logged'

echo "Podman machine runtime checks passed"
