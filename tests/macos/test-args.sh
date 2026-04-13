#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

assert_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if ! grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nmissing: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

assert_rejects_args() {
  local script_path="$1"
  local expected_message="$2"
  local error_file="$TMPDIR/$(basename "$script_path").err"

  if "$script_path" unexpected >/dev/null 2> "$error_file"; then
    printf 'assertion failed: %s should reject unexpected arguments\n' "$script_path" >&2
    exit 1
  fi

  assert_contains "$error_file" "$expected_message" "script reports invalid argument usage clearly"
}

assert_rejects_args "$ROOT/scripts/macos/brew-bootstrap" 'takes no arguments'
assert_rejects_args "$ROOT/scripts/macos/brew-configure" 'takes no arguments'
assert_rejects_args "$ROOT/scripts/macos/caddy-trust" 'takes no arguments'
assert_rejects_args "$ROOT/scripts/macos/caddy-service" 'takes exactly 1 argument'
assert_rejects_args "$ROOT/scripts/macos/brew-service" 'takes exactly 1 argument'
assert_rejects_args "$ROOT/scripts/macos/devtools-configure" 'takes no arguments'
assert_rejects_args "$ROOT/scripts/macos/podman-check" 'takes no arguments'
assert_rejects_args "$ROOT/scripts/macos/git-configure" 'takes no arguments'
assert_rejects_args "$ROOT/scripts/macos/system-configure" 'takes no arguments'

assert_rejects_two_args() {
  local script_path="$1"
  local expected_message="$2"
  local error_file="$TMPDIR/$(basename "$script_path").two.err"

  if "$script_path" one two >/dev/null 2> "$error_file"; then
    printf 'assertion failed: %s should reject more than one argument\n' "$script_path" >&2
    exit 1
  fi

  assert_contains "$error_file" "$expected_message" "script reports excessive arguments clearly"
}

assert_rejects_two_args "$ROOT/scripts/macos/brew-install" 'takes at most 1 argument'
assert_rejects_two_args "$ROOT/scripts/macos/brew-upgrade" 'takes at most 1 argument'
assert_rejects_two_args "$ROOT/scripts/macos/caddy-configure" 'takes at most 1 argument'
assert_rejects_two_args "$ROOT/scripts/macos/ghostty-configure" 'takes at most 1 argument'
assert_rejects_two_args "$ROOT/scripts/macos/jj-configure" 'takes at most 1 argument'
assert_rejects_two_args "$ROOT/scripts/macos/nushell-configure" 'takes at most 1 argument'
assert_rejects_two_args "$ROOT/scripts/macos/podman-configure" 'takes at most 1 argument'

echo "Argument validation checks passed"
