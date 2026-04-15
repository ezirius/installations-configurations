#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
chmod +x "$MOCK_BIN/uname"

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

check_help "$ROOT/scripts/macos/brew-install"
check_help "$ROOT/scripts/macos/brew-upgrade"
check_help "$ROOT/scripts/macos/brew-configure"
assert_contains "$TMPDIR/brew-configure.out" 'caddy-configure' 'brew-configure help lists configured steps'
assert_contains "$TMPDIR/brew-configure.out" 'podman-configure' 'brew-configure help reflects the current config-driven workflow'
check_help "$ROOT/scripts/macos/brew-service"
assert_contains "$TMPDIR/brew-service.out" 'caddy-service' 'brew-service help lists managed services from config'
check_help "$ROOT/scripts/macos/caddy-configure"
check_help "$ROOT/scripts/macos/caddy-service"
check_help "$ROOT/scripts/macos/caddy-trust"
check_help "$ROOT/scripts/macos/podman-check"
PATH="$MOCK_BIN:$PATH" "$ROOT/scripts/macos/podman-check" --help >"$TMPDIR/podman-check-help.out"
assert_contains "$TMPDIR/podman-check-help.out" 'diagnose' 'podman-check help documents the diagnose mode'
check_help "$ROOT/scripts/macos/podman-configure"
check_help "$ROOT/scripts/macos/system-configure"
check_help "$ROOT/scripts/macos/brew-bootstrap"
assert_contains "$TMPDIR/brew-bootstrap.out" 'brew-install' 'brew-bootstrap help lists configured bootstrap steps'
assert_contains "$TMPDIR/brew-bootstrap.out" 'brew-service start' 'brew-bootstrap help shows the configured service action'

echo "Help checks passed"
