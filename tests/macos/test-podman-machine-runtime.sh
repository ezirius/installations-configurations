#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/podman-configure"
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
          printf '[{"State":{"Running":false}}]\n'
          exit 0
        fi
        exit 1
        ;;
      set)
        if [[ "${3:-}" == --help ]]; then
          printf '%s\n' '--cpus --memory --disk-size --rootful'
          exit 0
        fi
        ;;
      init)
        : > "$STATE_DIR/machine.exists"
        ;;
      start)
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
cmp "$ROOT/config/podman/containers.conf" "$HOME_DIR/.config/containers/containers.conf"
assert_contains "$STATE_DIR/podman.log" 'machine init podman-machine-default' 'podman machine is initialised'
assert_contains "$STATE_DIR/podman.log" 'machine start podman-machine-default' 'podman machine is started'
LOG_FILE="$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers/Maldoria Installations and Configurations-$(date '+%Y%m%d')---------.csv"
assert_contains "$LOG_FILE" 'Podman machine' 'podman machine creation is logged'

STATE_DIR="$TMPDIR/state-existing"
mkdir -p "$STATE_DIR"
cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
case "$1" in
  machine)
    case "$2" in
      inspect)
        if [[ -f "$STATE_DIR/after-update" ]]; then
          printf '[{"State":{"Running":true},"cpus":4}]\n'
        else
          printf '[{"State":{"Running":true},"cpus":2}]\n'
        fi
        ;;
      set)
        if [[ "${3:-}" == --help ]]; then
          printf '%s\n' '--cpus --memory'
          exit 0
        fi
        if [[ "$3" == --cpus || "$3" == --memory ]]; then
          : > "$STATE_DIR/after-update"
        elif [[ "$3" == --disk-size || "$3" == --rootful ]]; then
          printf 'unsupported option invoked: %s\n' "$3" >&2
          exit 1
        fi
        ;;
      stop)
        ;;
      start)
        ;;
      *) exit 1 ;;
    esac
    ;;
  info)
    if [[ -f "$STATE_DIR/after-update" ]]; then
      printf '{}\n'
    else
      exit 1
    fi
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >/dev/null
assert_contains "$STATE_DIR/podman.log" 'machine set --cpus 4 podman-machine-default' 'supported podman machine options are applied'
assert_contains "$STATE_DIR/podman.log" 'machine set --memory 4096 podman-machine-default' 'supported podman memory option is applied'
assert_contains "$STATE_DIR/podman.log" 'machine stop podman-machine-default' 'running podman machine is stopped before applying mutable settings'
assert_contains "$STATE_DIR/podman.log" 'machine start podman-machine-default' 'running podman machine is restarted after applying mutable settings'
if grep -Fq -- '--disk-size' "$STATE_DIR/podman.log" || grep -Fq -- '--rootful' "$STATE_DIR/podman.log"; then
  printf 'assertion failed: unsupported podman machine options should be skipped\n' >&2
  exit 1
fi
assert_contains "$LOG_FILE" '"Podman machine","Updated"' 'podman machine update is logged when inspect output changes'

STATE_DIR="$TMPDIR/state-noop"
mkdir -p "$STATE_DIR"
cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
case "$1" in
  machine)
    case "$2" in
      inspect)
        printf '[{"State":{"Running":false},"cpus":4,"memory":4096}]\n'
        ;;
      set)
        if [[ "${3:-}" == --help ]]; then
          printf '%s\n' '--cpus --memory'
          exit 0
        fi
        ;;
      start|stop)
        printf 'unexpected lifecycle action\n' >&2
        exit 1
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
chmod +x "$MOCK_BIN/podman"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >/dev/null
if grep -Fq -- 'machine start podman-machine-default' "$STATE_DIR/podman.log" || grep -Fq -- 'machine stop podman-machine-default' "$STATE_DIR/podman.log"; then
  printf 'assertion failed: existing healthy podman machine should not be restarted when settings are unchanged\n' >&2
  exit 1
fi

echo "Podman machine runtime checks passed"
