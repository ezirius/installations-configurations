#!/usr/bin/env bash
# Shared characterization test for the active Homebrew workflow.
#
# This test covers:
# - layered Brewfile resolution across shared and OS scopes
# - install-only-missing behavior
# - help output for the active script contract
# - strict rejection of unsupported Brewfile directives
# - documentation headers for active config, library, script, and test files
# - per-host CSV activity logging
#
# It uses a temporary fake repo plus stubbed system commands so behavior can be
# verified without mutating the real machine.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT_SOURCE="$ROOT/scripts/shared/brew/brew-install"

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
    \\#*|\#*) return 0 ;;
  esac
  fail "$message"
}

assert_starts_with_heading() {
  local file_path="$1"
  local message="$2"
  local first_non_blank

  first_non_blank="$(grep -v '^[[:space:]]*$' "$file_path" | sed -n '1p')"
  case "$first_non_blank" in
    \#*) return 0 ;;
  esac
  fail "$message"
}

# Create an isolated fake repo that mirrors the active script and library paths.
make_fake_repo() {
  local temp_dir="$1"

  mkdir -p \
    "$temp_dir/scripts/shared/brew" \
    "$temp_dir/configs/shared/brew" \
    "$temp_dir/configs/shared/shared" \
    "$temp_dir/configs/macos/brew" \
    "$temp_dir/fake-bin" \
    "$temp_dir/libs/shared"
  cp "$SCRIPT_SOURCE" "$temp_dir/scripts/shared/brew/brew-install"
  if [[ -f "$ROOT/libs/shared/shared/common.sh" ]]; then
    mkdir -p "$temp_dir/libs/shared/shared"
    cp "$ROOT/libs/shared/shared/common.sh" "$temp_dir/libs/shared/shared/common.sh"
  fi
  cp "$ROOT/configs/shared/shared/logging-shared.conf" "$temp_dir/configs/shared/shared/logging-shared.conf"
  cp "$ROOT/configs/shared/brew/brew-install-shared.conf" "$temp_dir/configs/shared/brew/brew-install-shared.conf"
  chmod +x "$temp_dir/scripts/shared/brew/brew-install"
}

# Write a small executable stub used to isolate external command behavior.
write_command_stub() {
  local path="$1"
  local body="$2"

  printf '%s\n' "$body" > "$path"
  chmod +x "$path"
}

# Provide deterministic uname, hostname, whoami, date, and curl behavior.
setup_common_stubs() {
  local temp_dir="$1"
  local fake_bin="$temp_dir/fake-bin"

  write_command_stub "$fake_bin/uname" '#!/usr/bin/env bash
printf "%s\n" "${TEST_UNAME:-Darwin}"'

  write_command_stub "$fake_bin/hostname" '#!/usr/bin/env bash
printf "%s\n" "${TEST_HOSTNAME:-maldoria.local}"'

  write_command_stub "$fake_bin/whoami" '#!/usr/bin/env bash
printf "%s\n" "${TEST_WHOAMI:-ezirius}"'

  write_command_stub "$fake_bin/date" '#!/usr/bin/env bash
case "$1" in
  +%Y%m%d)
    printf "%s\n" "${TEST_DATE_YYYYMMDD:-20260427}"
    ;;
  +%H%M%S)
    printf "%s\n" "${TEST_TIME_HHMMSS:-143015}"
    ;;
  *)
    exit 1
    ;;
esac'

  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
if [[ "${TEST_BOOTSTRAP_BREW:-0}" == "1" ]]; then
  cat <<'INSTALLER'
#!/usr/bin/env bash
cat > "${TEST_FAKE_BIN:?}/brew" <<'BREWEOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${TEST_STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/brew.log"

case "$1" in
  --version)
    printf 'Homebrew 5.1.8\n'
    ;;
  list)
    if [[ "$2" == "--versions" ]]; then
      if grep -Fxq -- "$3" "$STATE_DIR/installed-formulae" 2>/dev/null; then
        printf '%s 1.0\n' "$3"
      else
        exit 1
      fi
    elif [[ "$2" == "--cask" && "$3" == "--versions" ]]; then
      if grep -Fxq -- "$4" "$STATE_DIR/installed-casks" 2>/dev/null; then
        printf '%s 1.0\n' "$4"
      else
        exit 1
      fi
    else
      exit 1
    fi
    ;;
  install)
    if [[ "$2" == "--cask" ]]; then
      printf '%s\n' "$3" >> "$STATE_DIR/installed-casks"
    else
      printf '%s\n' "$2" >> "$STATE_DIR/installed-formulae"
    fi
    ;;
  shellenv)
    :
    ;;
  *)
    printf 'unexpected brew command: %s\n' "$*" >&2
    exit 1
    ;;
esac
BREWEOF
chmod +x "${TEST_FAKE_BIN:?}/brew"
INSTALLER
  exit 0
fi
printf "curl should not be called\n" >&2
exit 1
EOF
  chmod +x "$fake_bin/curl"
}

# Provide a fake brew command that records install/list/update calls.
setup_brew_stub() {
  local temp_dir="$1"
  local fake_bin="$temp_dir/fake-bin"
  local brew_stub="$fake_bin/brew"

  cat > "$brew_stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${TEST_STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/brew.log"

case "$1" in
  --version)
    if [[ "${TEST_BREW_VERSION_MULTILINE:-0}" == "1" ]]; then
      i=1
      while [[ "$i" -le 2000 ]]; do
        if [[ "$i" -eq 1 ]]; then
          printf 'Homebrew 5.1.8\n'
        else
          printf 'extra-version-line-%s\n' "$i"
        fi
        i=$((i + 1))
      done
    else
      printf 'Homebrew 5.1.8\n'
    fi
    ;;
  update)
    :
    ;;
  list)
    if [[ "$2" == "--versions" ]]; then
      if grep -Fxq -- "$3" "$STATE_DIR/installed-formulae" 2>/dev/null; then
        printf '%s 1.0\n' "$3"
      else
        exit 1
      fi
    elif [[ "$2" == "--cask" && "$3" == "--versions" ]]; then
      if grep -Fxq -- "$4" "$STATE_DIR/installed-casks" 2>/dev/null; then
        printf '%s 1.0\n' "$4"
      else
        exit 1
      fi
    else
      exit 1
    fi
    ;;
  install)
    if [[ "${TEST_BREW_INSTALL_READS_STDIN:-0}" == "1" ]]; then
      if IFS= read -r _maybe_stdin; then
        :
      fi
    fi
    if [[ "$2" == "--cask" ]]; then
      printf '%s\n' "$3" >> "$STATE_DIR/installed-casks"
    else
      printf '%s\n' "$2" >> "$STATE_DIR/installed-formulae"
    fi
    ;;
  bundle)
    printf 'brew bundle should not be called\n' >&2
    exit 1
    ;;
  shellenv)
    :
    ;;
  *)
    printf 'unexpected brew command: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF

  chmod +x "$brew_stub"
}

# Run the active script inside the fake repo with stubbed commands.
run_in_fake_repo() {
  local temp_dir="$1"
  local output_file="$2"

  TEST_STATE_DIR="$temp_dir/state" \
  TEST_FAKE_BIN="$temp_dir/fake-bin" \
  HOMEBREW_SKIP_STANDARD_PREFIX_SHELLENV="${HOMEBREW_SKIP_STANDARD_PREFIX_SHELLENV:-0}" \
  PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$temp_dir/scripts/shared/brew/brew-install" > "$output_file" 2>&1
}

test_selects_layered_brewfiles_and_installs_missing_only() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"
  printf 'opencode\n' > "$temp_dir/state/installed-formulae"
  printf 'ghostty\n' > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/shared/brew/Brewfile-shared-ezirius" <<'EOF'
brew "opencode"
brew "ripgrep"
EOF

  cat > "$temp_dir/configs/shared/brew/Brewfile-maldoria-ezirius" <<'EOF'
cask "ghostty"
cask "utm"
EOF

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  cat > "$temp_dir/configs/macos/brew/Brewfile-maldoria-ezirius" <<'EOF'
cask "vscodium"
EOF

  cat > "$temp_dir/configs/macos/brew/Brewfile-other-ezirius" <<'EOF'
brew "should-not-install"
EOF

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-otheruser" <<'EOF'
brew "wrong-user"
EOF

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should succeed when matching Brewfiles exist'
  fi

  assert_contains "$temp_dir/state/brew.log" 'install ripgrep' 'installs missing shared formula'
  assert_contains "$temp_dir/state/brew.log" 'install nushell' 'installs missing os formula'
  assert_contains "$temp_dir/state/brew.log" 'install --cask utm' 'installs missing shared host cask'
  assert_contains "$temp_dir/state/brew.log" 'install --cask vscodium' 'installs missing os host cask'
  assert_not_contains "$temp_dir/state/brew.log" 'update' 'brew-install should not run brew update'
  assert_not_contains "$temp_dir/state/brew.log" 'install opencode' 'skips installed formula'
  assert_not_contains "$temp_dir/state/brew.log" 'install --cask ghostty' 'skips installed cask'
  assert_not_contains "$temp_dir/state/brew.log" 'should-not-install' 'ignores other host brewfile'
  assert_not_contains "$temp_dir/state/brew.log" 'wrong-user' 'ignores other username brewfile'
  assert_contains "$output_file" 'Brewfile-shared-ezirius' 'prints selected shared brewfile'
  assert_contains "$output_file" 'Brewfile-maldoria-ezirius' 'prints selected host brewfile'
}

test_fails_when_no_matching_brewfiles_exist() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'script should fail when no matching Brewfiles exist'
  fi

  assert_contains "$output_file" 'No matching Brewfiles found' 'reports missing brewfiles'
}

test_selects_linux_brewfiles() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state" "$temp_dir/configs/linux/brew"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/linux/brew/Brewfile-shared-ezirius" <<'EOF'
brew "fd"
EOF

  if ! TEST_UNAME=Linux run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should succeed when linux Brewfiles exist'
  fi

  assert_contains "$temp_dir/state/brew.log" 'install fd' 'uses linux brewfile when uname is Linux'
}

test_help_output() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  if ! PATH="$temp_dir/fake-bin:$PATH" "$temp_dir/scripts/shared/brew/brew-install" --help > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'script should show help successfully'
  fi

  assert_contains "$output_file" 'Usage: brew-install' 'shows help usage'
  assert_contains "$output_file" '[-h|--help]' 'documents both help flags'
  assert_contains "$output_file" 'Brewfile-<host>-<username>' 'documents Brewfile naming in help'
}

test_short_help_output() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  if ! PATH="$temp_dir/fake-bin:$PATH" "$temp_dir/scripts/shared/brew/brew-install" -h > "$output_file" 2>&1; then
    cat "$output_file" >&2
    fail 'script should show short help successfully'
  fi

  assert_contains "$output_file" 'Usage: brew-install' 'shows short help usage'
  assert_contains "$output_file" '[-h|--help]' 'documents both help flags in short help'
  assert_contains "$output_file" 'Brewfile-<host>-<username>' 'documents Brewfile naming in short help'
}

test_rejects_positional_arguments() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  if PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$temp_dir/scripts/shared/brew/brew-install" unexpected > "$output_file" 2>&1; then
    fail 'brew-install should fail when given positional arguments'
  fi

  assert_contains "$output_file" 'ERROR: brew-install takes no arguments. Use --help for usage.' 'brew-install should use the aligned invalid-argument message'
}

test_rejects_invalid_brewfile_line() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
tap "homebrew/cask"
EOF

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'script should reject unsupported Brewfile directives'
  fi

  assert_contains "$output_file" 'Unsupported Brewfile line' 'reports invalid Brewfile lines clearly'
}

test_rejects_brewfile_line_with_trailing_content() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "ripgrep" trailing-content
EOF

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'script should reject Brewfile entries with trailing content'
  fi

  assert_contains "$output_file" 'Unsupported Brewfile line' 'rejects Brewfile entries with trailing content'
}

test_cleans_up_temp_files_when_brewfile_parse_fails() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state" "$temp_dir/tmp"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "ripgrep" trailing-content
EOF

  if TMPDIR="$temp_dir/tmp" run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'script should reject Brewfile entries with trailing content'
  fi

  assert_contains "$output_file" 'Unsupported Brewfile line' 'rejects invalid Brewfile lines during parse'
  if [[ -n "$(ls -A "$temp_dir/tmp")" ]]; then
    fail 'brew-install should clean up temporary files when Brewfile parsing fails'
  fi
}

test_rejects_single_quoted_brew_entry() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew 'ripgrep'
EOF

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'script should reject single-quoted brew entries'
  fi

  assert_contains "$output_file" 'Unsupported Brewfile line' 'rejects single-quoted brew entries'
}

test_rejects_single_quoted_cask_entry() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
cask 'ghostty'
EOF

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'script should reject single-quoted cask entries'
  fi

  assert_contains "$output_file" 'Unsupported Brewfile line' 'rejects single-quoted cask entries'
}

test_active_files_are_documented() {
  assert_starts_with_comment "$ROOT/configs/macos/brew/Brewfile-shared-ezirius" 'active Brewfile should start with a header comment'
  assert_starts_with_comment "$ROOT/configs/shared/brew/brew-install-shared.conf" 'shared brew runtime config should start with a header comment'
  assert_starts_with_comment "$ROOT/configs/shared/shared/logging-shared.conf" 'shared logging config should start with a header comment'
  assert_starts_with_comment "$ROOT/configs/macos/downloads/macos-download-shared.conf" 'macos downloads runtime config should start with a header comment'
  assert_starts_with_comment "$ROOT/configs/macos/system/system-settings-shared.conf" 'active system config should start with a header comment'
  assert_starts_with_comment "$ROOT/libs/shared/shared/common.sh" 'shared library should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/scripts/shared/brew/brew-install" 'active script should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/scripts/shared/shared/bootstrap" 'active bootstrap script should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/scripts/macos/downloads/macos-download" 'active macos download script should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/scripts/macos/system/system-configure" 'active system script should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/tests/shared/brew/test-brew-install.sh" 'active test should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/tests/shared/downloads/test-macos-download.sh" 'active macos download test should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/tests/shared/shared/test-bootstrap.sh" 'active bootstrap test should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/tests/shared/system/test-system-configure.sh" 'active system test should start with a header comment after shebang'
  assert_starts_with_heading "$ROOT/README.md" 'README should start with a markdown heading'
  assert_starts_with_heading "$ROOT/AGENTS.md" 'AGENTS should start with a markdown heading'
  assert_contains "$ROOT/tests/shared/brew/test-brew-install.sh" 'This test covers:' 'active test header should describe covered behaviours'
  assert_contains "$ROOT/tests/shared/downloads/test-macos-download.sh" 'This test covers:' 'active macos download test header should describe covered behaviours'
  assert_contains "$ROOT/tests/shared/shared/test-bootstrap.sh" 'This test covers:' 'active bootstrap test header should describe covered behaviours'
  assert_contains "$ROOT/tests/shared/system/test-system-configure.sh" 'This test covers:' 'active system test header should describe covered behaviours'
  assert_contains "$ROOT/README.md" 'All active scripts, libs, tests, configs, and docs should be well documented.' 'README should state the documentation requirement'
  assert_contains "$ROOT/README.md" '- macOS system configuration with host-specific override and shared fallback settings files' 'README should describe the current system config fallback model'
  assert_contains "$ROOT/README.md" '- `<host>` is either `shared` or the current hostname normalised to lowercase up to the first `.`' 'README should document host normalisation'
  assert_contains "$ROOT/README.md" '- `<username>` is `whoami`, normalised to lowercase with non-alphanumeric characters converted to `-`' 'README should document username normalisation'
  assert_contains "$ROOT/README.md" '- leading and trailing `-` characters are trimmed' 'README should document trimming dash runs'
  assert_contains "$ROOT/README.md" '- repeated `-` characters are collapsed' 'README should document collapsing repeated dashes'
  assert_contains "$ROOT/AGENTS.md" 'Every active script, config, shared library, test file, and doc must be well documented.' 'AGENTS should state the documentation requirement'
}

test_gitignore_repo_hygiene_rules() {
  if [[ "$(sed -n '1p' "$ROOT/.gitignore")" != '.DS_Store' ]]; then
    fail '.gitignore should keep hidden entries first'
  fi

  if [[ "$(sed -n '2p' "$ROOT/.gitignore")" != '.worktrees/' ]]; then
    fail '.gitignore should keep hidden entries in alphabetical order'
  fi

  if [[ "$(sed -n '3p' "$ROOT/.gitignore")" != '/downloads/' ]]; then
    fail '.gitignore should ignore the repo-local downloads/ before logs/'
  fi

  if [[ "$(sed -n '4p' "$ROOT/.gitignore")" != '/logs/' ]]; then
    fail '.gitignore should ignore the repo-local logs/'
  fi
}

test_logs_new_installs_to_csv() {
  local temp_dir
  local output_file
  local log_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  log_file="$temp_dir/logs/macos/shared/installations-and-configurations-maldoria.csv"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"
  printf 'opencode\n' > "$temp_dir/state/installed-formulae"
  printf 'ghostty\n' > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/shared/brew/Brewfile-shared-ezirius" <<'EOF'
brew "opencode"
brew "ripgrep"
EOF

  cat > "$temp_dir/configs/macos/brew/Brewfile-maldoria-ezirius" <<'EOF'
cask "ghostty"
cask "vscodium"
EOF

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should succeed when logging installs'
  fi

  assert_contains "$log_file" 'date,time,host,action,application,version' 'log file should contain csv header'
  assert_contains "$log_file" '20260427,143015,maldoria,Installed,ripgrep,' 'log formula install row'
  assert_contains "$log_file" '20260427,143015,maldoria,Installed,vscodium,' 'log cask install row'
  assert_not_contains "$log_file" ',Installed,brew,' 'should not log Homebrew when brew already exists'
  assert_not_contains "$temp_dir/state/brew.log" 'update' 'install logging path should not run brew update'
  assert_not_contains "$log_file" 'opencode' 'should not log skipped installed formula'
  assert_not_contains "$log_file" 'ghostty' 'should not log skipped installed cask'
}

test_child_commands_do_not_consume_brewfile_input() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
brew "ripgrep"
cask "vscodium"
EOF

  if ! TEST_BREW_INSTALL_READS_STDIN=1 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should succeed even if brew install reads stdin'
  fi

  assert_contains "$temp_dir/state/brew.log" 'install nushell' 'installs first entry even when child reads stdin'
  assert_contains "$temp_dir/state/brew.log" 'install ripgrep' 'installs later formula even when child reads stdin'
  assert_contains "$temp_dir/state/brew.log" 'install --cask vscodium' 'installs cask even when child reads stdin'
  assert_not_contains "$output_file" 'brew|ripgrep' 'parsed entries should not leak to output'
  assert_not_contains "$output_file" 'cask|vscodium' 'parsed cask entries should not leak to output'
}

test_bootstraps_homebrew_and_logs_it() {
  local temp_dir
  local output_file
  local log_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  log_file="$temp_dir/logs/macos/shared/installations-and-configurations-maldoria.csv"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  if ! TEST_BOOTSTRAP_BREW=1 HOMEBREW_SKIP_STANDARD_PREFIX_SHELLENV=1 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should bootstrap Homebrew when brew is missing'
  fi

  assert_contains "$temp_dir/state/brew.log" '--version' 'bootstrapped brew should be available after install'
  assert_contains "$temp_dir/state/brew.log" 'install nushell' 'managed installs should continue after bootstrap'
  assert_contains "$log_file" '20260427,143015,maldoria,Installed,brew,5.1.8' 'log bootstrap Homebrew install row'
  assert_contains "$log_file" '20260427,143015,maldoria,Installed,nushell,' 'log managed install after bootstrap'
  assert_not_contains "$temp_dir/state/brew.log" 'update' 'bootstrap path should not run brew update'
}

test_fails_clearly_when_bootstrap_curl_is_missing() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  rm -f "$temp_dir/fake-bin/curl"
  write_command_stub "$temp_dir/fake-bin/dirname" '#!/usr/bin/env bash
exec /usr/bin/dirname "$@"'
  write_command_stub "$temp_dir/fake-bin/tr" '#!/usr/bin/env bash
exec /usr/bin/tr "$@"'
  write_command_stub "$temp_dir/fake-bin/sed" '#!/usr/bin/env bash
exec /usr/bin/sed "$@"'

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  if TEST_STATE_DIR="$temp_dir/state" \
    TEST_FAKE_BIN="$temp_dir/fake-bin" \
    HOMEBREW_SKIP_STANDARD_PREFIX_SHELLENV=1 \
    PATH="$temp_dir/fake-bin:/bin:/usr/sbin:/sbin" \
    "$temp_dir/scripts/shared/brew/brew-install" > "$output_file" 2>&1; then
    fail 'script should fail clearly when curl is missing during Homebrew bootstrap'
  fi

  assert_contains "$output_file" 'ERROR: Required command is missing: curl' 'bootstrap path should fail clearly when curl is unavailable'
}

test_requires_brew_installer_config_file() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"
  rm -f "$temp_dir/configs/shared/brew/brew-install-shared.conf"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'script should fail when the required brew installer config file is missing'
  fi

  assert_contains "$output_file" 'ERROR: Required config not found:' 'brew installer should fail clearly when the config file is missing'
}

test_handles_multiline_brew_version_output() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  if ! TEST_BREW_VERSION_MULTILINE=1 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should tolerate multiline brew --version output'
  fi

  assert_contains "$temp_dir/state/brew.log" '--version' 'checks brew version on the normal success path'
  assert_contains "$temp_dir/state/brew.log" 'install nushell' 'continues installs after printing brew version'
}

test_requires_logging_values_from_config_file() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/shared/shared/logging-shared.conf" <<'EOF'
# Shared logging defaults for all supported OS scopes and account names.
ACTIVITY_LOG_ROOT_RELATIVE="logs"
ACTIVITY_LOG_SCOPE_SUBDIR="shared"
ACTIVITY_LOG_FILE_PREFIX="installations-and-configurations"
ACTIVITY_LOG_CSV_HEADER="date,time,host,action,application,version"
ACTION_INSTALLED="Installed"
ACTION_UPDATED="Updated"
ACTION_REMOVED="Removed"
EOF

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  if ACTIVITY_LOG_TIMEZONE='Africa/Johannesburg' run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'script should fail when a required logging value is missing from config even if exported in the environment'
  fi

  assert_contains "$output_file" 'ERROR: Required config value is not set: ACTIVITY_LOG_TIMEZONE' 'requires logging values to be defined by the config file itself'
}

test_active_shell_files_pass_bash_syntax_check() {
  bash -n "$ROOT/libs/shared/shared/common.sh" || fail 'common.sh should pass bash -n'
  bash -n "$ROOT/scripts/shared/brew/brew-install" || fail 'brew-install should pass bash -n'
  bash -n "$ROOT/scripts/shared/shared/bootstrap" || fail 'bootstrap should pass bash -n'
  bash -n "$ROOT/scripts/macos/downloads/macos-download" || fail 'macos-download should pass bash -n'
  bash -n "$ROOT/scripts/macos/system/system-configure" || fail 'system-configure should pass bash -n'
}

test_selects_layered_brewfiles_and_installs_missing_only
test_fails_when_no_matching_brewfiles_exist
test_selects_linux_brewfiles
test_help_output
test_short_help_output
test_rejects_positional_arguments
test_rejects_invalid_brewfile_line
test_rejects_brewfile_line_with_trailing_content
test_cleans_up_temp_files_when_brewfile_parse_fails
test_rejects_single_quoted_brew_entry
test_rejects_single_quoted_cask_entry
test_active_files_are_documented
test_gitignore_repo_hygiene_rules
test_logs_new_installs_to_csv
test_child_commands_do_not_consume_brewfile_input
test_bootstraps_homebrew_and_logs_it
test_fails_clearly_when_bootstrap_curl_is_missing
test_requires_brew_installer_config_file
test_handles_multiline_brew_version_output
test_requires_logging_values_from_config_file
test_active_shell_files_pass_bash_syntax_check

printf 'PASS: tests/shared/brew/test-brew-install.sh\n'
