#!/usr/bin/env bash
# Shared characterization test for the root install bootstrap workflow.
#
# This test covers:
# - help output and argument handling for the public curl entrypoint
# - fresh clone into the fixed user-local destination
# - in-place updates for existing same-repo clones across HTTPS and SSH origins
# - clear failures for conflicting existing paths and different repositories
# - documentation headers and shell syntax for the root install script
#
# It uses a temporary fake repo plus a stubbed git command so behaviour can be
# verified without cloning the real repository or mutating the real home folder.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT_SOURCE="$ROOT/install"

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

  mkdir -p "$temp_dir/fake-bin"
  cp "$SCRIPT_SOURCE" "$temp_dir/install"
  chmod +x "$temp_dir/install"
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

  write_command_stub "$fake_bin/git" '#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${TEST_STATE_DIR:?}"
printf "%s\n" "$*" >> "$STATE_DIR/git.log"

case "$1" in
  clone)
    destination="$3"
    mkdir -p "$destination/.git"
    printf "%s\n" "${TEST_CLONE_REMOTE_URL:-$2}" > "$destination/.git/origin-url"
    exit 0
    ;;
  -C)
    repo_path="$2"
    shift 2
    case "$1" in
      rev-parse)
        [[ -d "$repo_path/.git" ]] || exit 1
        printf "%s\n" "$repo_path"
        exit 0
        ;;
      remote)
        if [[ "$2" == "get-url" && "$3" == "origin" ]]; then
          [[ -f "$repo_path/.git/origin-url" ]] || exit 1
          /bin/cat "$repo_path/.git/origin-url"
          exit 0
        fi
        exit 1
        ;;
      fetch)
        [[ "${TEST_GIT_FETCH_FAIL:-0}" == "1" ]] && exit 1
        exit 0
        ;;
      pull)
        [[ "${TEST_GIT_PULL_FAIL:-0}" == "1" ]] && {
          printf "%s\n" "fatal: Not possible to fast-forward, aborting." >&2
          exit 1
        }
        exit 0
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac'
}

run_in_fake_repo() {
  local temp_dir="$1"
  local output_file="$2"

  HOME="$temp_dir/home" \
  TEST_STATE_DIR="$temp_dir/state" \
  PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$temp_dir/install" > "$output_file" 2>&1
}

install_destination() {
  local temp_dir="$1"

  printf '%s\n' "$temp_dir/home/.local/share/installations-and-configurations"
}

test_help_output() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"

  if ! "$temp_dir/install" --help > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'install should show help successfully'
  fi

  assert_contains "$output_file" 'Usage: install [--help]' 'shows install help usage'
  assert_contains "$output_file" '~/.local/share/installations-and-configurations' 'documents fixed install destination'
  assert_contains "$output_file" 'curl -fsSL https://raw.githubusercontent.com/ezirius/installations-and-configurations/main/install | bash' 'documents public one-line install command'
}

test_rejects_positional_arguments() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"

  if "$temp_dir/install" unexpected > "$output_file" 2>&1; then
    fail 'install should fail when given positional arguments'
  fi

  assert_contains "$output_file" 'ERROR: install takes no arguments. Use --help for usage.' 'install should reject unexpected arguments with the aligned message'
}

test_clones_when_destination_is_missing() {
  local temp_dir
  local output_file
  local destination

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  destination="$(install_destination "$temp_dir")"
  mkdir -p "$temp_dir/state"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'install should clone the repo when the destination is missing'
  fi

  assert_contains "$temp_dir/state/git.log" "clone https://github.com/ezirius/installations-and-configurations.git $destination" 'install should clone the public HTTPS repo into the fixed destination'
  [[ -d "$destination/.git" ]] || fail 'install should create the destination git directory'
  assert_contains "$output_file" 'Installed installations-and-configurations to ' 'install should report a successful fresh install'
  assert_contains "$output_file" "$destination/scripts/shared/shared/bootstrap" 'install should print the next bootstrap command'
}

test_updates_existing_https_clone() {
  local temp_dir
  local output_file
  local destination

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  destination="$(install_destination "$temp_dir")"
  mkdir -p "$temp_dir/state" "$destination/.git"
  printf '%s\n' 'https://github.com/ezirius/installations-and-configurations.git' > "$destination/.git/origin-url"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'install should update an existing same-repo HTTPS clone'
  fi

  assert_contains "$temp_dir/state/git.log" "-C $destination fetch --prune origin" 'install should fetch before updating an existing clone'
  assert_contains "$temp_dir/state/git.log" "-C $destination pull --ff-only origin main" 'install should fast-forward pull the existing clone'
  assert_contains "$output_file" 'Updated installations-and-configurations in ' 'install should report a successful update'
}

test_updates_existing_ssh_clone() {
  local temp_dir
  local output_file
  local destination

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  destination="$(install_destination "$temp_dir")"
  mkdir -p "$temp_dir/state" "$destination/.git"
  printf '%s\n' 'git@github.com:ezirius/installations-and-configurations.git' > "$destination/.git/origin-url"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'install should update an existing same-repo SSH clone'
  fi

  assert_contains "$temp_dir/state/git.log" "-C $destination fetch --prune origin" 'install should fetch before updating an existing SSH clone'
  assert_contains "$temp_dir/state/git.log" "-C $destination pull --ff-only origin main" 'install should fast-forward pull the existing SSH clone'
}

test_updates_existing_ssh_url_clone() {
  local temp_dir
  local output_file
  local destination

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  destination="$(install_destination "$temp_dir")"
  mkdir -p "$temp_dir/state" "$destination/.git"
  printf '%s\n' 'ssh://git@github.com/ezirius/installations-and-configurations.git' > "$destination/.git/origin-url"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'install should update an existing same-repo ssh:// clone'
  fi

  assert_contains "$temp_dir/state/git.log" "-C $destination fetch --prune origin" 'install should fetch before updating an existing ssh:// clone'
  assert_contains "$temp_dir/state/git.log" "-C $destination pull --ff-only origin main" 'install should fast-forward pull the existing ssh:// clone'
}

test_fails_when_destination_is_not_a_git_repo() {
  local temp_dir
  local output_file
  local destination

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  destination="$(install_destination "$temp_dir")"
  mkdir -p "$temp_dir/state" "$destination"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'install should fail when the destination exists but is not a git repo'
  fi

  assert_contains "$output_file" 'ERROR: Existing install path is not a git repository:' 'install should fail clearly for a non-git destination directory'
}

test_fails_when_destination_is_a_file() {
  local temp_dir
  local output_file
  local destination

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  destination="$(install_destination "$temp_dir")"
  mkdir -p "$temp_dir/state" "$(dirname "$destination")"
  printf 'not a directory\n' > "$destination"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'install should fail when the destination path is a file'
  fi

  assert_contains "$output_file" 'ERROR: Existing install path is not a directory:' 'install should fail clearly for a non-directory destination path'
}

test_fails_when_existing_repo_points_elsewhere() {
  local temp_dir
  local output_file
  local destination

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  destination="$(install_destination "$temp_dir")"
  mkdir -p "$temp_dir/state" "$destination/.git"
  printf '%s\n' 'https://github.com/ezirius/different-repo.git' > "$destination/.git/origin-url"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'install should fail when the existing repo points at a different origin'
  fi

  assert_contains "$output_file" 'ERROR: Existing install path points to a different repository:' 'install should fail clearly for a different existing repo'
}

test_fails_cleanly_when_fast_forward_update_fails() {
  local temp_dir
  local output_file
  local destination

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  destination="$(install_destination "$temp_dir")"
  mkdir -p "$temp_dir/state" "$destination/.git"
  printf '%s\n' 'https://github.com/ezirius/installations-and-configurations.git' > "$destination/.git/origin-url"
  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  if TEST_GIT_PULL_FAIL=1 run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'install should fail when fast-forward update is not possible'
  fi

  assert_contains "$output_file" 'ERROR: Unable to fast-forward the existing installations-and-configurations clone.' 'install should fail clearly when git pull --ff-only fails'
  assert_not_contains "$temp_dir/state/git.log" 'clone https://github.com/ezirius/installations-and-configurations.git' 'install should not re-clone after a failed update'
}

test_documentation_headers() {
  assert_starts_with_comment "$ROOT/install" 'install should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/tests/shared/shared/test-install.sh" 'install test should start with a header comment after shebang'
}

test_shell_syntax() {
  bash -n "$ROOT/install" || fail 'install should pass bash -n'
}

test_help_output
test_rejects_positional_arguments
test_clones_when_destination_is_missing
test_updates_existing_https_clone
test_updates_existing_ssh_clone
test_updates_existing_ssh_url_clone
test_fails_when_destination_is_not_a_git_repo
test_fails_when_destination_is_a_file
test_fails_when_existing_repo_points_elsewhere
test_fails_cleanly_when_fast_forward_update_fails
test_documentation_headers
test_shell_syntax

printf 'PASS: tests/shared/shared/test-install.sh\n'
