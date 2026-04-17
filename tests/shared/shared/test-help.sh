#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
MOCK_LINUX_BIN="$TMPDIR/linux-bin"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$MOCK_BIN"
mkdir -p "$MOCK_LINUX_BIN"
cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
chmod +x "$MOCK_BIN/uname"

cat > "$MOCK_LINUX_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Linux\n'
EOF
chmod +x "$MOCK_LINUX_BIN/uname"

assert_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nmissing: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

check_help() {
  local script_path="$1"
  local output_file="$TMPDIR/$(basename "$script_path").out"
  PATH="$MOCK_BIN:$PATH" "$script_path" --help >"$output_file"
  assert_contains "$output_file" 'Usage:' "help output includes a usage header"
  assert_contains "$output_file" "$(basename "$script_path")" "help output names the script"
}

check_help_on_linux() {
  local script_path="$1"
  local output_file="$TMPDIR/linux-$(basename "$script_path").out"
  PATH="$MOCK_LINUX_BIN:$PATH" "$script_path" --help >"$output_file"
  assert_contains "$output_file" 'Usage:' "linux help output includes a usage header"
  assert_contains "$output_file" "$(basename "$script_path")" "linux help output names the script"
}

check_help "$ROOT/scripts/brew/macos/brew-install"
check_help "$ROOT/scripts/brew/macos/brew-upgrade"
check_help "$ROOT/scripts/brew/macos/brew-configure"
assert_contains "$TMPDIR/brew-configure.out" 'caddy-configure' 'brew-configure help lists configured steps'
assert_contains "$TMPDIR/brew-configure.out" 'podman-configure' 'brew-configure help reflects the current config-driven workflow'
assert_contains "$TMPDIR/brew-configure.out" 'system-configure' 'brew-configure help reflects system-configure in the configured step list'
check_help_on_linux "$ROOT/scripts/brew/macos/brew-configure"
assert_contains "$TMPDIR/linux-brew-configure.out" 'caddy-configure' 'brew-configure help stays config-driven off macOS'
check_help "$ROOT/scripts/brew/macos/brew-service"
assert_contains "$TMPDIR/brew-service.out" 'caddy-service' 'brew-service help lists managed services from config'
check_help_on_linux "$ROOT/scripts/brew/macos/brew-service"
assert_contains "$TMPDIR/linux-brew-service.out" 'caddy-service' 'brew-service help lists managed services off macOS'
check_help "$ROOT/scripts/caddy/macos/caddy-configure"
check_help "$ROOT/scripts/caddy/macos/caddy-service"
check_help "$ROOT/scripts/caddy/macos/caddy-trust"
check_help "$ROOT/scripts/podman/macos/podman-check"
PATH="$MOCK_BIN:$PATH" "$ROOT/scripts/podman/macos/podman-check" --help >"$TMPDIR/podman-check-help.out"
assert_contains "$TMPDIR/podman-check-help.out" 'diagnose' 'podman-check help documents the diagnose mode'
check_help "$ROOT/scripts/podman/macos/podman-configure"
assert_contains "$TMPDIR/podman-configure.out" 'Asks for approval before applying managed machine-setting changes' 'podman-configure help documents the approval prompt'
assert_contains "$TMPDIR/podman-configure.out" 'If approval is declined, Podman reconciliation is bypassed' 'podman-configure help documents the bypass behavior'
check_help "$ROOT/scripts/system/macos/system-configure"
check_help "$ROOT/scripts/brew/macos/brew-bootstrap"
assert_contains "$TMPDIR/brew-bootstrap.out" 'brew-install' 'brew-bootstrap help lists configured bootstrap steps'
assert_contains "$TMPDIR/brew-bootstrap.out" 'brew-service start' 'brew-bootstrap help shows the configured service action'
check_help_on_linux "$ROOT/scripts/brew/macos/brew-bootstrap"
assert_contains "$TMPDIR/linux-brew-bootstrap.out" 'brew-install' 'brew-bootstrap help lists configured bootstrap steps off macOS'
assert_contains "$TMPDIR/linux-brew-bootstrap.out" 'brew-service start' 'brew-bootstrap help shows the configured service action off macOS'

echo "Help checks passed"
