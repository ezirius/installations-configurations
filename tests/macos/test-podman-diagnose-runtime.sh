#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPERS="$ROOT/tests/lib/runtime-helpers.sh"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
MOCK_BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
HOME_DIR="$TMPDIR/home"
SCRIPT_FILE="$REPO_DIR/scripts/macos/podman-check"

mkdir -p "$MOCK_BIN" "$STATE_DIR" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$REPO_DIR/scripts/macos" "$REPO_DIR/lib/shell" "$REPO_DIR/config/podman" "$REPO_DIR/config/repo"
trap 'rm -rf "$TMPDIR" /tmp/podman-diagnose-absolute' EXIT
source "$HELPERS"

cp "$ROOT/scripts/macos/podman-check" "$REPO_DIR/scripts/macos/podman-check"
cp "$ROOT/lib/shell/common.sh" "$REPO_DIR/lib/shell/common.sh"
cp "$ROOT/config/repo/shared.conf" "$REPO_DIR/config/repo/shared.conf"

cat > "$REPO_DIR/config/podman/shared-macos.conf" <<'EOF'
PODMAN_SOURCE_RELATIVE_PATH="config/podman/containers.conf"
PODMAN_TARGET_RELATIVE_PATH=".config/containers/containers.conf"
PODMAN_MACHINE_NAME_DEFAULT="podman-machine-default"
PODMAN_MACHINE_STORAGE_RELATIVE_PATH=".local/share/containers/podman/machine"
PODMAN_CHECK_IMAGE="docker.io/library/alpine:3.22"
PODMAN_CHECK_COMMAND=(echo "Hello from podman")
PODMAN_DIAGNOSE_OUTPUT_DIR="logs/podman"
PODMAN_DIAGNOSE_EVENT_WINDOWS=(
  "5m"
  "30m"
)
PODMAN_DIAGNOSE_HOST_COMMANDS=(
  "uptime"
  "df -h /"
)
PODMAN_DIAGNOSE_MACHINE_COMMANDS=(
  "uptime"
  "df -h"
)
EOF

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
printf 'Maldoria/Mac\n'
EOF

cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
case "$*" in
  'version')
    printf 'client version\n'
    ;;
  'machine list')
    printf 'NAME RUNNING\n'
    ;;
  'machine inspect podman-machine-default')
    printf '[{"Name":"podman-machine-default"}]\n'
    ;;
  'machine ssh podman-machine-default bash -lc uptime')
    printf 'machine:bash -lc uptime\n'
    ;;
  'info')
    printf '{"host":"ok"}\n'
    ;;
  'ps')
    printf 'container-list\n'
    ;;
  'ps -a')
    printf 'all-container-list\n'
    ;;
  'images')
    printf 'image-list\n'
    ;;
  'system df')
    printf 'storage-usage\n'
    ;;
  'events --stream=false --since 5m')
    printf 'event-stream\n'
    ;;
  'events --stream=false --since 30m')
    printf 'event-stream\n'
    ;;
  'run --rm docker.io/library/alpine:3.22 echo Hello from podman')
    printf 'Hello from podman\n'
    ;;
  *)
    printf 'unhandled podman call: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/xcode-select" "$MOCK_BIN/scutil" "$MOCK_BIN/podman"

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" diagnose >"$STATE_DIR/out" 2>"$STATE_DIR/err"

REPORT_DIR="$REPO_DIR/logs/podman"
report_count=$(find "$REPORT_DIR" -maxdepth 1 -type f -name '*.log' | wc -l)
if [[ "$report_count" != "1" ]]; then
  printf 'assertion failed: podman-check diagnose should write exactly one report file\n' >&2
  exit 1
fi

REPORT_FILE=$(find "$REPORT_DIR" -maxdepth 1 -type f -name '*.log' | head -n 1)
case "$REPORT_FILE" in
  *'Maldoria-Mac Podman Diagnose-'*) ;;
  *)
    printf 'assertion failed: diagnose mode should name the report with safe_log_host_name\nfile: %s\n' "$REPORT_FILE" >&2
    exit 1
    ;;
esac
assert_contains "$STATE_DIR/out" '## Podman Diagnose' 'diagnose mode prints a formatted report header'
assert_contains "$REPORT_FILE" '## Podman Diagnose' 'diagnose mode saves a formatted report header'
assert_contains "$REPORT_FILE" '## Summary' 'diagnose report includes a deterministic summary section'
assert_contains "$REPORT_FILE" '### host uptime' 'diagnose report includes host-side diagnostics'
assert_contains "$REPORT_FILE" '### podman system df' 'diagnose report includes storage diagnostics'
assert_contains "$REPORT_FILE" '### podman machine ssh -- uptime' 'diagnose report includes machine SSH diagnostics'
assert_contains "$STATE_DIR/podman.log" 'events --stream=false --since 5m' 'diagnose mode captures a bounded short recent Podman event snapshot'
assert_contains "$STATE_DIR/podman.log" 'events --stream=false --since 30m' 'diagnose mode captures a bounded recent Podman event snapshot'
assert_contains "$STATE_DIR/podman.log" 'machine ssh podman-machine-default bash -lc uptime' 'diagnose mode targets the configured machine explicitly'

cat > "$REPO_DIR/config/podman/shared-macos.conf" <<'EOF'
PODMAN_SOURCE_RELATIVE_PATH="config/podman/containers.conf"
PODMAN_TARGET_RELATIVE_PATH=".config/containers/containers.conf"
PODMAN_MACHINE_NAME_DEFAULT="podman-machine-default"
PODMAN_MACHINE_STORAGE_RELATIVE_PATH=".local/share/containers/podman/machine"
PODMAN_CHECK_IMAGE="docker.io/library/alpine:3.22"
PODMAN_CHECK_COMMAND=(echo "Hello from podman")
PODMAN_DIAGNOSE_OUTPUT_DIR="/tmp/podman-diagnose-absolute"
PODMAN_DIAGNOSE_EVENT_WINDOWS=(
  "5m"
)
PODMAN_DIAGNOSE_HOST_COMMANDS=(
  "uptime"
)
PODMAN_DIAGNOSE_MACHINE_COMMANDS=(
  "uptime"
)
EOF

cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
case "$*" in
  'version')
    printf 'client version\n'
    ;;
  'machine list')
    printf 'NAME RUNNING\n'
    ;;
  'machine inspect podman-machine-default')
    printf '[{"Name":"podman-machine-default"}]\n'
    ;;
  'machine ssh podman-machine-default bash -lc uptime')
    printf 'machine:bash -lc uptime\n'
    ;;
  'info')
    printf 'broken info\n' >&2
    exit 42
    ;;
  'ps')
    printf 'container-list\n'
    ;;
  'ps -a')
    printf 'all-container-list\n'
    ;;
  'images')
    printf 'image-list\n'
    ;;
  'system df')
    printf 'storage-usage\n'
    ;;
  'events --stream=false --since 5m')
    printf 'event-stream\n'
    ;;
  'run --rm docker.io/library/alpine:3.22 echo Hello from podman')
    printf 'Hello from podman\n'
    ;;
  *)
    printf 'unhandled podman call: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"

ABS_DIR="/tmp/podman-diagnose-absolute"
rm -rf "$ABS_DIR"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" diagnose >"$STATE_DIR/abs.out" 2>"$STATE_DIR/abs.err"
ABS_REPORT_FILE=$(find "$ABS_DIR" -maxdepth 1 -type f -name '*.log' | head -n 1)
test -n "$ABS_REPORT_FILE"
assert_contains "$ABS_REPORT_FILE" 'Commands with non-zero exit status: 1' 'diagnose summary records failing subcommands'
assert_contains "$ABS_REPORT_FILE" '[exit status: 42]' 'diagnose report records non-zero command exit statuses'

echo "Podman diagnose runtime checks passed"
