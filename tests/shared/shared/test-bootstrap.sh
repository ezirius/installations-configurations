#!/usr/bin/env bash
# Shared characterization test for the active shared bootstrap workflow.
#
# This test covers:
# - help output and argument handling
# - running brew-install before macOS system-configure on macOS
# - running only shared workflows on Linux when no Linux-specific follow-up exists
# - stopping on the first failure
# - documentation headers for the bootstrap script and test file
#
# It uses a temporary fake repo plus stubbed child scripts so behavior can be
# verified without mutating the real machine.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT_SOURCE="$ROOT/scripts/shared/shared/bootstrap"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local file_path="$1"
  local expected="$2"
  local message="$3"

  if ! grep -Fq -- "$expected" "$file_path"; then
    printf 'Expected to find: %s\n' "$expected" >&2
    fail "$message"
  fi
}

assert_not_contains() {
  local file_path="$1"
  local unexpected="$2"
  local message="$3"

  if grep -Fq -- "$unexpected" "$file_path"; then
    printf 'Did not expect to find: %s\n' "$unexpected" >&2
    fail "$message"
  fi
}

assert_starts_with_comment() {
  local file_path="$1"
  local message="$2"
  local first_non_shebang

  first_non_shebang="$(grep -v '^#!' "$file_path" | grep -v '^[[:space:]]*$' | sed -n '1p')"
  case "$first_non_shebang" in
    \#*|\\#*) return 0 ;;
  esac
  fail "$message"
}

make_fake_repo() {
  local temp_dir="$1"

  mkdir -p \
    "$temp_dir/scripts/shared/shared" \
    "$temp_dir/scripts/shared/brew" \
    "$temp_dir/scripts/macos/system" \
    "$temp_dir/fake-bin" \
    "$temp_dir/libs/shared/shared"
  cp "$SCRIPT_SOURCE" "$temp_dir/scripts/shared/shared/bootstrap"
  cp "$ROOT/libs/shared/shared/common.sh" "$temp_dir/libs/shared/shared/common.sh"
  chmod +x "$temp_dir/scripts/shared/shared/bootstrap"
}

write_command_stub() {
  local path="$1"
  local body="$2"

  printf '%s\n' "$body" > "$path"
  chmod +x "$path"
}

setup_common_stubs() {
  local temp_dir="$1"
  local fake_bin="$temp_dir/fake-bin"

  write_command_stub "$fake_bin/uname" '#!/usr/bin/env bash
printf "%s\n" "${TEST_UNAME:-Darwin}"'
}

write_child_script() {
  local path="$1"
  local body="$2"

  printf '%s\n' "$body" > "$path"
  chmod +x "$path"
}

run_in_fake_repo() {
  local temp_dir="$1"
  local output_file="$2"

  TEST_STATE_DIR="$temp_dir/state" \
  PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$temp_dir/scripts/shared/shared/bootstrap" > "$output_file" 2>&1
}

test_help_output() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  if ! "$temp_dir/scripts/shared/shared/bootstrap" --help > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'bootstrap should show help successfully'
  fi

  assert_contains "$output_file" 'Usage: bootstrap' 'shows bootstrap help usage'
  assert_contains "$output_file" 'brew-install' 'documents brew-install step'
  assert_contains "$output_file" 'system-configure' 'documents system-configure step'
}

test_rejects_positional_arguments() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  if "$temp_dir/scripts/shared/shared/bootstrap" unexpected > "$output_file" 2>&1; then
    fail 'bootstrap should fail when given positional arguments'
  fi

  assert_contains "$output_file" 'ERROR: bootstrap takes no arguments. Use --help for usage.' 'bootstrap should use the aligned invalid-argument message'
}

test_runs_brew_then_system() {
  local temp_dir
  local output_file
  local call_log

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  call_log="$temp_dir/state/calls.log"
  mkdir -p "$temp_dir/state"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_child_script "$temp_dir/scripts/shared/brew/brew-install" '#!/usr/bin/env bash
printf "%s\n" "brew-install" >> "$TEST_STATE_DIR/calls.log"'
  write_child_script "$temp_dir/scripts/macos/system/system-configure" '#!/usr/bin/env bash
printf "%s\n" "system-configure" >> "$TEST_STATE_DIR/calls.log"'
  setup_common_stubs "$temp_dir"

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'bootstrap should run successfully when child scripts succeed'
  fi

  assert_contains "$call_log" 'brew-install' 'bootstrap should run brew-install'
  assert_contains "$call_log" 'system-configure' 'bootstrap should run system-configure'
  if [[ "$(sed -n '1p' "$call_log")" != 'brew-install' ]]; then
    fail 'bootstrap should run brew-install first'
  fi
  if [[ "$(sed -n '2p' "$call_log")" != 'system-configure' ]]; then
    fail 'bootstrap should run system-configure second'
  fi
}

test_stops_when_brew_fails() {
  local temp_dir
  local output_file
  local call_log

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  call_log="$temp_dir/state/calls.log"
  mkdir -p "$temp_dir/state"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_child_script "$temp_dir/scripts/shared/brew/brew-install" '#!/usr/bin/env bash
printf "%s\n" "brew-install" >> "$TEST_STATE_DIR/calls.log"
exit 1'
  write_child_script "$temp_dir/scripts/macos/system/system-configure" '#!/usr/bin/env bash
printf "%s\n" "system-configure" >> "$TEST_STATE_DIR/calls.log"'
  setup_common_stubs "$temp_dir"

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'bootstrap should fail when brew-install fails'
  fi

  assert_contains "$call_log" 'brew-install' 'bootstrap should run brew-install before failing'
  assert_not_contains "$call_log" 'system-configure' 'bootstrap should not run system-configure after brew-install fails'
}

test_runs_only_shared_workflows_on_linux() {
  local temp_dir
  local output_file
  local call_log

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  call_log="$temp_dir/state/calls.log"
  mkdir -p "$temp_dir/state"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  write_child_script "$temp_dir/scripts/shared/brew/brew-install" '#!/usr/bin/env bash
printf "%s\n" "brew-install" >> "$TEST_STATE_DIR/calls.log"'
  setup_common_stubs "$temp_dir"

  if ! TEST_UNAME=Linux run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'bootstrap should succeed on Linux when only the shared Brew workflow exists'
  fi

  assert_contains "$call_log" 'brew-install' 'bootstrap should run brew-install on Linux'
  assert_not_contains "$call_log" 'system-configure' 'bootstrap should skip macOS-only system-configure on Linux'
}

test_documentation_headers() {
  assert_starts_with_comment "$ROOT/scripts/shared/shared/bootstrap" 'bootstrap script should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/tests/shared/shared/test-bootstrap.sh" 'bootstrap test should start with a header comment after shebang'
}

test_help_output
test_rejects_positional_arguments
test_runs_brew_then_system
test_stops_when_brew_fails
test_runs_only_shared_workflows_on_linux
test_documentation_headers

printf 'PASS: tests/shared/shared/test-bootstrap.sh\n'
