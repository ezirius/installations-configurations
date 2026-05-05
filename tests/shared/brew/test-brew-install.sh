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

assert_path_missing() {
  local path="$1"
  local message="$2"

  if [[ -e "$path" || -L "$path" ]]; then
    printf 'Unexpected path exists: %s\n' "$path" >&2
    fail "$message"
  fi
}

assert_occurrences() {
  local file_path="$1"
  local expected_text="$2"
  local expected_count="$3"
  local message="$4"
  local actual_count

  actual_count="$(grep -F -c -- "$expected_text" "$file_path" || true)"
  if [[ "$actual_count" != "$expected_count" ]]; then
    printf 'Expected %s occurrences of: %s\n' "$expected_count" "$expected_text" >&2
    printf 'Actual occurrences: %s\n' "$actual_count" >&2
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
  cp "$ROOT/configs/shared/shared/logging.conf" "$temp_dir/configs/shared/shared/logging.conf"
  cp "$ROOT/configs/shared/brew/brew-install.conf" "$temp_dir/configs/shared/brew/brew-install.conf"
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
STATE_DIR="${TEST_STATE_DIR:?}"
printf 'NONINTERACTIVE=%s\n' "${NONINTERACTIVE:-}" > "$STATE_DIR/bootstrap-env.log"

if [[ "${TEST_BOOTSTRAP_INSTALLER_FAIL:-0}" == "1" ]]; then
  printf '%s\n' 'Need sudo access on macOS (e.g. the user ezirius needs to be an Administrator)!' >&2
  exit 1
fi

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

  write_command_stub "$fake_bin/dseditgroup" '#!/usr/bin/env bash
if [[ "${TEST_IS_ADMIN:-1}" == "1" ]]; then
  exit 0
fi
exit 1'
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

  command mkdir -p "$temp_dir/home"

  TEST_STATE_DIR="$temp_dir/state" \
  TEST_FAKE_BIN="$temp_dir/fake-bin" \
  HOME="$temp_dir/home" \
  HOMEBREW_SKIP_STANDARD_PREFIX_SHELLENV="${HOMEBREW_SKIP_STANDARD_PREFIX_SHELLENV:-0}" \
  PATH="$temp_dir/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$temp_dir/scripts/shared/brew/brew-install" > "$output_file" 2>&1
}

shell_block_marker() {
  printf '%s\n' '# >>> installations-and-configurations homebrew shellenv >>>'
}

zshenv_block_marker() {
  printf '%s\n' '# >>> installations-and-configurations homebrew path >>>'
}

nushell_block_marker() {
  printf '%s\n' '# >>> installations-and-configurations homebrew path >>>'
}

canonical_nushell_config_path() {
  local home_path="$1"
  printf '%s/.config/nushell/config.nu\n' "$home_path"
}

macos_nushell_compatibility_dir() {
  local home_path="$1"
  printf '%s/Library/Application Support/nushell\n' "$home_path"
}

linux_nushell_config_path() {
  local home_path="$1"
  printf '%s/.config/nushell/config.nu\n' "$home_path"
}

assert_shell_setup_files() {
  local home_path="$1"
  local os_name="$2"
  local nushell_config_path="$3"
  local compatibility_dir

  assert_contains "$home_path/.zshenv" 'export PATH="' 'writes zshenv Homebrew path block'
  assert_contains "$home_path/.zshenv" ':$PATH"' 'appends the existing PATH in zshenv'
  assert_contains "$home_path/.zprofile" 'brew shellenv zsh' 'writes zsh shellenv block'
  assert_contains "$home_path/.bash_profile" 'brew shellenv bash' 'writes bash profile shellenv block'
  assert_contains "$home_path/.bashrc" 'brew shellenv bash' 'writes bashrc shellenv block'
  assert_occurrences "$home_path/.zshenv" "$(zshenv_block_marker)" 1 'writes one zshenv managed block'
  assert_occurrences "$home_path/.zprofile" "$(shell_block_marker)" 1 'writes one zsh managed block'
  assert_occurrences "$home_path/.bash_profile" "$(shell_block_marker)" 1 'writes one bash profile managed block'
  assert_occurrences "$home_path/.bashrc" "$(shell_block_marker)" 1 'writes one bashrc managed block'
  assert_contains "$nushell_config_path" 'let brew_bin =' 'writes Nushell brew bin path'
  assert_contains "$nushell_config_path" 'let brew_sbin =' 'writes Nushell brew sbin path'
  assert_contains "$nushell_config_path" 'not-in $env.PATH' 'guards Nushell path prepends'
  assert_occurrences "$nushell_config_path" "$(nushell_block_marker)" 1 'writes one Nushell managed block'

  if [[ "$os_name" == 'macos' ]]; then
    compatibility_dir="$(macos_nushell_compatibility_dir "$home_path")"
    [[ -L "$compatibility_dir" ]] || fail 'macOS should create a Nushell compatibility symlink'
    [[ "$(readlink "$compatibility_dir")" == "$home_path/.config/nushell" ]] || fail 'macOS compatibility symlink should point to the canonical Nushell dir'
  fi
}

test_selects_layered_brewfiles_and_installs_missing_only() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/configs/linux/brew"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"
  printf 'ripgrep\n' > "$temp_dir/state/installed-formulae"
  printf 'ghostty\n' > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/shared/brew/Brewfile-shared-shared" <<'EOF'
brew "fd"
EOF

  cat > "$temp_dir/configs/shared/brew/Brewfile-shared-ezirius" <<'EOF'
brew "ripgrep"
EOF

  cat > "$temp_dir/configs/shared/brew/Brewfile-maldoria-shared" <<'EOF'
cask "utm"
EOF

  cat > "$temp_dir/configs/shared/brew/Brewfile-maldoria-ezirius" <<'EOF'
cask "ghostty"
cask "tailscale-app"
EOF

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-shared" <<'EOF'
brew "wget"
EOF

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  cat > "$temp_dir/configs/macos/brew/Brewfile-maldoria-shared" <<'EOF'
cask "podman-desktop"
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

  cat > "$temp_dir/configs/linux/brew/Brewfile-shared-shared" <<'EOF'
brew "wrong-os"
EOF

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should succeed when matching Brewfiles exist'
  fi

  assert_contains "$temp_dir/state/brew.log" 'install fd' 'installs missing shared shared formula'
  assert_contains "$temp_dir/state/brew.log" 'install wget' 'installs missing os shared shared formula'
  assert_contains "$temp_dir/state/brew.log" 'install nushell' 'installs missing os shared user formula'
  assert_contains "$temp_dir/state/brew.log" 'install --cask utm' 'installs missing shared host shared cask'
  assert_contains "$temp_dir/state/brew.log" 'install --cask tailscale-app' 'installs missing shared host user cask'
  assert_contains "$temp_dir/state/brew.log" 'install --cask podman-desktop' 'installs missing os host shared cask'
  assert_contains "$temp_dir/state/brew.log" 'install --cask vscodium' 'installs missing os host user cask'
  assert_not_contains "$temp_dir/state/brew.log" 'update' 'brew-install should not run brew update'
  assert_not_contains "$temp_dir/state/brew.log" 'install ripgrep' 'skips installed shared user formula'
  assert_not_contains "$temp_dir/state/brew.log" 'install --cask ghostty' 'skips installed shared host user cask'
  assert_not_contains "$temp_dir/state/brew.log" 'should-not-install' 'ignores other host brewfile'
  assert_not_contains "$temp_dir/state/brew.log" 'wrong-user' 'ignores other username brewfile'
  assert_not_contains "$temp_dir/state/brew.log" 'wrong-os' 'ignores other os brewfile'
  assert_contains "$output_file" 'Brewfile-shared-shared' 'prints selected shared shared brewfile'
  assert_contains "$output_file" 'Brewfile-shared-ezirius' 'prints selected shared user brewfile'
  assert_contains "$output_file" 'Brewfile-maldoria-shared' 'prints selected host shared brewfile'
  assert_contains "$output_file" 'Brewfile-maldoria-ezirius' 'prints selected host user brewfile'
  assert_contains "$output_file" 'WARNING: Enable macOS Local Network access for these apps in System Settings > Privacy & Security > Local Network. This is needed, for example, to connect to the Multipass VM shell from the CLI:' 'prints Local Network warning heading after successful install runs'
  assert_contains "$output_file" 'Enable Local Network access for: Ghostty' 'prints Ghostty Local Network warning when Ghostty is already installed from the matched config'
  assert_contains "$output_file" 'Enable Local Network access for: VSCodium' 'prints VSCodium Local Network warning when VSCodium is newly installed from the matched config'
  assert_not_contains "$output_file" 'Enable Local Network access for: Multipass' 'does not warn for configured items that are absent from the matched config'
}

test_warns_for_already_installed_configured_item_in_matched_brewfiles() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"
  printf 'ghostty\n' > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
cask "ghostty"
EOF

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should warn for already installed configured items in matched Brewfiles'
  fi

  assert_contains "$output_file" 'Enable Local Network access for: Ghostty' 'warns for already installed configured item in the matched config'
}

test_warns_for_newly_installed_configured_item_in_matched_brewfiles() {
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
cask "vscodium"
EOF

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should warn for newly installed configured items in matched Brewfiles'
  fi

  assert_contains "$output_file" 'Enable Local Network access for: VSCodium' 'warns for newly installed configured item in the matched config'
}

test_does_not_warn_for_configured_item_not_in_matched_brewfiles() {
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

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should ignore configured warning items that are absent from matched Brewfiles'
  fi

  assert_not_contains "$output_file" 'Enable Local Network access for: Multipass' 'does not warn for configured items absent from matched Brewfiles'
}

test_does_not_warn_for_non_configured_item_even_if_installed() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"
  printf 'utm\n' > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
cask "utm"
EOF

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should not warn for installed items that are not configured for Local Network warnings'
  fi

  assert_not_contains "$output_file" 'Enable Local Network access for:' 'does not warn for non-configured installed items'
}

test_does_not_print_warning_heading_when_no_relevant_warning_items_exist() {
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

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should suppress the Local Network warning heading when nothing relevant matches'
  fi

  assert_not_contains "$output_file" 'WARNING: Enable macOS Local Network access for these apps in System Settings > Privacy & Security > Local Network.' 'does not print the Local Network warning heading when nothing relevant matches'
}

test_warn_matching_is_type_agnostic() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"
  printf 'multipass\n' > "$temp_dir/state/installed-formulae"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "multipass"
EOF

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should match Local Network warnings by token regardless of brew or cask entry type'
  fi

  assert_contains "$output_file" 'Enable Local Network access for: Multipass' 'matches configured warning items by token regardless of entry type'
}

test_fails_clearly_when_missing_cask_user_is_not_admin() {
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
cask "vscodium"
EOF

  if TEST_IS_ADMIN=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'script should fail early when a missing cask would require admin rights'
  fi

  assert_contains "$output_file" 'ERROR: Cask installs on macOS require an Administrator account: vscodium' 'fails clearly when a missing cask install requires admin rights'
  assert_not_contains "$temp_dir/state/brew.log" 'install --cask vscodium' 'does not attempt the cask install after the admin guard fails'
}

test_skips_installed_cask_without_admin_failure() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  printf 'vscodium\n' > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
cask "vscodium"
EOF

  if ! TEST_IS_ADMIN=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should still skip already installed casks without admin failure'
  fi

  assert_contains "$output_file" 'Skipping installed cask: vscodium' 'skips already installed cask without admin failure'
}

test_missing_formula_still_installs_without_admin_guard() {
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
brew "ripgrep"
EOF

  if ! TEST_IS_ADMIN=0 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should still install missing formulae without the cask admin guard'
  fi

  assert_contains "$temp_dir/state/brew.log" 'install ripgrep' 'installs missing formula without admin guard'
}

test_supports_shared_shared_brewfile() {
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

  cat > "$temp_dir/configs/shared/brew/Brewfile-shared-shared" <<'EOF'
brew "fd"
EOF

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should succeed when only the shared shared Brewfile exists'
  fi

  assert_contains "$temp_dir/state/brew.log" 'install fd' 'installs from shared shared Brewfile'
  assert_contains "$output_file" 'Brewfile-shared-shared' 'prints selected shared shared Brewfile'
}

test_supports_host_shared_brewfile() {
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

  cat > "$temp_dir/configs/shared/brew/Brewfile-shared-ezirius" <<'EOF'
brew "ripgrep"
EOF

  cat > "$temp_dir/configs/shared/brew/Brewfile-maldoria-shared" <<'EOF'
cask "utm"
EOF

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should support a host shared Brewfile layer'
  fi

  assert_contains "$temp_dir/state/brew.log" 'install ripgrep' 'installs from shared user Brewfile'
  assert_contains "$temp_dir/state/brew.log" 'install --cask utm' 'installs from host shared Brewfile'
  assert_contains "$output_file" 'Brewfile-maldoria-shared' 'prints selected host shared Brewfile'
}

test_current_real_style_brewfiles_still_work() {
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

  cat > "$temp_dir/configs/macos/brew/Brewfile-maldoria-ezirius" <<'EOF'
cask "vscodium"
EOF

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should keep current real-style Brewfile resolution working unchanged'
  fi

  assert_contains "$temp_dir/state/brew.log" 'install nushell' 'installs from current shared user Brewfile'
  assert_contains "$temp_dir/state/brew.log" 'install --cask vscodium' 'installs from current host user Brewfile'
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
  assert_contains "$output_file" "<host> and <username> each support 'shared'" 'documents shared support in both Brewfile naming slots'
  assert_contains "$output_file" 'configs/shared/brew/Brewfile-shared-shared' 'documents shared shared Brewfile resolution in help'
  assert_contains "$output_file" 'configs/<os>/brew/Brewfile-<host>-<username>' 'documents full 8-layer Brewfile resolution in help'
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
  assert_contains "$output_file" "<host> and <username> each support 'shared'" 'documents shared support in both Brewfile naming slots in short help'
  assert_contains "$output_file" 'configs/shared/brew/Brewfile-shared-shared' 'documents shared shared Brewfile resolution in short help'
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
  [[ -x "$ROOT/install" ]] || fail 'root install script should be executable'
  [[ -x "$ROOT/scripts/shared/brew/brew-install" ]] || fail 'active brew script should be executable'
  [[ -x "$ROOT/scripts/shared/shared/bootstrap" ]] || fail 'active bootstrap script should be executable'
  [[ -x "$ROOT/scripts/macos/downloads/macos-download" ]] || fail 'active macos download script should be executable'
  [[ -x "$ROOT/scripts/macos/system/system-configure" ]] || fail 'active system script should be executable'
  assert_starts_with_comment "$ROOT/install" 'root install script should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/configs/shared/system/system-configure.conf" 'active system support config should start with a header comment'
  assert_starts_with_comment "$ROOT/configs/macos/brew/Brewfile-shared-ezirius" 'active Brewfile should start with a header comment'
  assert_starts_with_comment "$ROOT/configs/shared/brew/brew-install.conf" 'brew installer runtime config should start with a header comment'
  assert_starts_with_comment "$ROOT/configs/shared/shared/logging.conf" 'shared logging config should start with a header comment'
  assert_starts_with_comment "$ROOT/configs/macos/downloads/macos-download.conf" 'macos downloads runtime config should start with a header comment'
  assert_starts_with_comment "$ROOT/configs/shared/system/system-shared-shared.conf" 'active shared system config should start with a header comment'
  assert_starts_with_comment "$ROOT/configs/macos/system/system-maldoria-shared.conf" 'active host-shared macOS system config should start with a header comment'
  assert_starts_with_comment "$ROOT/libs/shared/shared/common.sh" 'shared library should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/scripts/shared/brew/brew-install" 'active script should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/scripts/shared/shared/bootstrap" 'active bootstrap script should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/scripts/macos/downloads/macos-download" 'active macos download script should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/scripts/macos/system/system-configure" 'active system script should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/tests/shared/brew/test-brew-install.sh" 'active test should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/tests/shared/downloads/test-macos-download.sh" 'active macos download test should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/tests/shared/shared/test-install.sh" 'active install test should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/tests/shared/shared/test-bootstrap.sh" 'active bootstrap test should start with a header comment after shebang'
  assert_starts_with_comment "$ROOT/tests/shared/system/test-system-configure.sh" 'active system test should start with a header comment after shebang'
  assert_starts_with_heading "$ROOT/README.md" 'README should start with a markdown heading'
  assert_starts_with_heading "$ROOT/AGENTS.md" 'AGENTS should start with a markdown heading'
  assert_contains "$ROOT/tests/shared/brew/test-brew-install.sh" 'This test covers:' 'active test header should describe covered behaviours'
  assert_contains "$ROOT/tests/shared/downloads/test-macos-download.sh" 'This test covers:' 'active macos download test header should describe covered behaviours'
  assert_contains "$ROOT/tests/shared/shared/test-install.sh" 'This test covers:' 'active install test header should describe covered behaviours'
  assert_contains "$ROOT/tests/shared/shared/test-bootstrap.sh" 'This test covers:' 'active bootstrap test header should describe covered behaviours'
  assert_contains "$ROOT/tests/shared/system/test-system-configure.sh" 'This test covers:' 'active system test header should describe covered behaviours'
  assert_contains "$ROOT/README.md" 'All active scripts, libs, tests, configs, and docs should be well documented.' 'README should state the documentation requirement'
  assert_contains "$ROOT/README.md" '- Public repo bootstrap install into a fixed per-user path' 'README should describe the root install workflow'
  assert_contains "$ROOT/README.md" '- macOS system configuration through layered shared, host, and user settings files' 'README should describe the layered system config model'
  assert_contains "$ROOT/README.md" 'curl -fsSL https://raw.githubusercontent.com/ezirius/installations-and-configurations/main/install | bash' 'README should document the public install command'
  assert_contains "$ROOT/README.md" '- `<host>` is either `shared` or the current hostname normalised to lowercase up to the first `.`' 'README should document host normalisation'
  assert_contains "$ROOT/README.md" '- `<username>` is either `shared` or `whoami`, normalised to lowercase with non-alphanumeric characters converted to `-`' 'README should document username normalisation'
  assert_contains "$ROOT/README.md" '- leading and trailing `-` characters are trimmed' 'README should document trimming dash runs'
  assert_contains "$ROOT/README.md" '- repeated `-` characters are collapsed' 'README should document collapsing repeated dashes'
  assert_contains "$ROOT/AGENTS.md" 'Keep all scripts, code, libraries, tests, configs, and active docs well documented.' 'AGENTS should state the documentation requirement'
  assert_contains "$ROOT/AGENTS.md" 'The root `install` bootstrap script is a special public entrypoint used before' 'AGENTS should document the root install bootstrap contract'
}

test_gitignore_repo_hygiene_rules() {
  local entries=()
  local hidden_entries=()
  local visible_entries=()
  local line
  local index
  local previous

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    entries+=("$line")
    if [[ "$line" == .* ]]; then
      hidden_entries+=("$line")
    else
      visible_entries+=("$line")
    fi
  done < "$ROOT/.gitignore"

  [[ " ${entries[*]} " == *' /downloads/ '* ]] || fail '.gitignore should ignore the repo-local downloads/'
  [[ " ${entries[*]} " == *' /logs/ '* ]] || fail '.gitignore should ignore the repo-local logs/'

  for ((index = 0; index < ${#entries[@]}; index++)); do
    if [[ "${entries[$index]}" != .* ]]; then
      break
    fi
  done

  for ((; index < ${#entries[@]}; index++)); do
    [[ "${entries[$index]}" != .* ]] || fail '.gitignore should keep hidden entries before non-hidden entries'
  done

  previous=''
  for line in "${hidden_entries[@]}"; do
    if [[ -n "$previous" && "$line" < "$previous" ]]; then
      fail '.gitignore should keep hidden entries in alphabetical order'
    fi
    previous="$line"
  done

  previous=''
  for line in "${visible_entries[@]}"; do
    if [[ -n "$previous" && "$line" < "$previous" ]]; then
      fail '.gitignore should keep non-hidden entries in alphabetical order'
    fi
    previous="$line"
  done
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

test_bootstraps_homebrew_interactively_when_tty_is_available() {
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

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  if ! TEST_BOOTSTRAP_BREW=1 TEST_FORCE_INTERACTIVE=1 HOMEBREW_SKIP_STANDARD_PREFIX_SHELLENV=1 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should bootstrap Homebrew interactively when a tty is available'
  fi

  assert_contains "$temp_dir/state/bootstrap-env.log" 'NONINTERACTIVE=' 'interactive bootstrap should not force NONINTERACTIVE=1'
  assert_not_contains "$temp_dir/state/bootstrap-env.log" 'NONINTERACTIVE=1' 'interactive bootstrap should allow the Homebrew installer to prompt'
}

test_bootstraps_homebrew_non_interactively_when_tty_is_unavailable() {
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

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  if ! TEST_BOOTSTRAP_BREW=1 TEST_FORCE_INTERACTIVE=0 HOMEBREW_SKIP_STANDARD_PREFIX_SHELLENV=1 run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should bootstrap Homebrew non-interactively when no tty is available'
  fi

  assert_contains "$temp_dir/state/bootstrap-env.log" 'NONINTERACTIVE=1' 'non-interactive bootstrap should force NONINTERACTIVE=1'
}

test_fails_clearly_when_homebrew_missing_and_user_is_not_admin() {
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

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  if TEST_BOOTSTRAP_BREW=1 TEST_IS_ADMIN=0 HOMEBREW_SKIP_STANDARD_PREFIX_SHELLENV=1 run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'script should fail early when Homebrew is missing and the user is not an admin'
  fi

  assert_contains "$output_file" 'ERROR: Homebrew bootstrap on macOS requires an Administrator account.' 'fails clearly when Homebrew bootstrap would require admin rights'
}

test_fails_clearly_when_non_interactive_homebrew_bootstrap_needs_sudo() {
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

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  if TEST_BOOTSTRAP_BREW=1 TEST_BOOTSTRAP_INSTALLER_FAIL=1 TEST_FORCE_INTERACTIVE=0 HOMEBREW_SKIP_STANDARD_PREFIX_SHELLENV=1 run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'script should fail clearly when non-interactive Homebrew bootstrap cannot prompt for sudo'
  fi

  assert_contains "$output_file" 'ERROR: Homebrew bootstrap requires sudo, but this run is non-interactive and cannot prompt for a password. Install Homebrew first or rerun from an interactive terminal.' 'non-interactive bootstrap should explain the sudo prompt limitation clearly'
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
  rm -f "$temp_dir/configs/shared/brew/brew-install.conf"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'script should fail when the required brew installer config file is missing'
  fi

  assert_contains "$output_file" 'ERROR: Required config not found:' 'brew installer should fail clearly when the config file is missing'
}

test_requires_brew_installer_values_from_config_file() {
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

  cat > "$temp_dir/configs/shared/brew/brew-install.conf" <<'EOF'
# Shared Homebrew installer runtime defaults for all supported OS scopes and account names.
#
# This file owns external bootstrap values used by scripts/shared/brew/brew-install.
# Missing required brew installer config is a hard failure.
EOF

  if HOMEBREW_INSTALL_URL='https://example.invalid/install.sh' run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'script should fail when a required brew installer value is missing from config even if exported in the environment'
  fi

  assert_contains "$output_file" 'ERROR: Required config value is not set: HOMEBREW_INSTALL_URL' 'requires brew installer values to be defined by the config file itself'
}

test_requires_local_network_warning_values_from_config_file() {
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

  cat > "$temp_dir/configs/shared/brew/brew-install.conf" <<'EOF'
# Shared Homebrew installer runtime defaults for all supported OS scopes and account names.
#
# This file owns external bootstrap values used by scripts/shared/brew/brew-install.
# Missing required brew installer config is a hard failure.

HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
LOCAL_NETWORK_WARNING_TITLE="WARNING: Enable macOS Local Network access for these apps in System Settings > Privacy & Security > Local Network."
EOF

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  if LOCAL_NETWORK_WARNING_ITEMS='ghostty:Wrong Source' run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'script should fail when required Local Network warning values are missing from config even if exported in the environment'
  fi

  assert_contains "$output_file" 'ERROR: Required config value is not set: LOCAL_NETWORK_WARNING_ITEMS' 'requires Local Network warning values to be defined by the config file itself'
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

  cat > "$temp_dir/configs/shared/shared/logging.conf" <<'EOF'
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

test_persists_shell_setup_when_brew_exists() {
  local temp_dir
  local output_file
  local home_path
  local nushell_config_path

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  home_path="$temp_dir/home"
  nushell_config_path="$(canonical_nushell_config_path "$home_path")"
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

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should persist shell setup when brew already exists'
  fi

  assert_shell_setup_files "$home_path" 'macos' "$nushell_config_path"
  assert_contains "$output_file" 'Configured shell startup for zsh, bash, and nushell' 'reports shell setup summary'
}

test_persists_shell_setup_after_homebrew_bootstrap() {
  local temp_dir
  local output_file
  local home_path
  local nushell_config_path

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  home_path="$temp_dir/home"
  nushell_config_path="$(canonical_nushell_config_path "$home_path")"
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
    fail 'script should persist shell setup after bootstrapping Homebrew'
  fi

  assert_shell_setup_files "$home_path" 'macos' "$nushell_config_path"
}

test_shell_setup_is_idempotent_on_rerun() {
  local temp_dir
  local output_file
  local home_path
  local nushell_config_path

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  home_path="$temp_dir/home"
  nushell_config_path="$(canonical_nushell_config_path "$home_path")"
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

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'first run should succeed when testing shell setup idempotence'
  fi

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'second run should succeed when testing shell setup idempotence'
  fi

  assert_occurrences "$home_path/.zshenv" "$(zshenv_block_marker)" 1 'zshenv managed block should not duplicate on rerun'
  assert_occurrences "$home_path/.zprofile" "$(shell_block_marker)" 1 'zprofile managed block should not duplicate on rerun'
  assert_occurrences "$home_path/.bash_profile" "$(shell_block_marker)" 1 'bash profile managed block should not duplicate on rerun'
  assert_occurrences "$home_path/.bashrc" "$(shell_block_marker)" 1 'bashrc managed block should not duplicate on rerun'
  assert_occurrences "$nushell_config_path" "$(nushell_block_marker)" 1 'Nushell managed block should not duplicate on rerun'
}

test_preserves_existing_shell_config_content() {
  local temp_dir
  local output_file
  local home_path
  local nushell_config_path

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  home_path="$temp_dir/home"
  nushell_config_path="$(canonical_nushell_config_path "$home_path")"
  mkdir -p "$temp_dir/state" "$(dirname "$nushell_config_path")"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"
  mkdir -p "$home_path"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$home_path/.zshenv" <<'EOF'
# existing zshenv line
export FOO=bar
EOF

  cat > "$home_path/.zprofile" <<'EOF'
# existing zprofile line
alias ll='ls -l'
EOF

  cat > "$home_path/.bash_profile" <<'EOF'
# existing bash profile line
export EDITOR=vi
EOF

  cat > "$home_path/.bashrc" <<'EOF'
# existing bashrc line
export HISTSIZE=1000
EOF

  cat > "$nushell_config_path" <<'EOF'
# existing config line
$env.config.show_banner = false
EOF

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should preserve existing shell config content'
  fi

  assert_contains "$home_path/.zshenv" 'export FOO=bar' 'preserves existing zshenv content'
  assert_contains "$home_path/.zprofile" "alias ll='ls -l'" 'preserves existing zprofile content'
  assert_contains "$home_path/.bash_profile" 'export EDITOR=vi' 'preserves existing bash profile content'
  assert_contains "$home_path/.bashrc" 'export HISTSIZE=1000' 'preserves existing bashrc content'
  assert_contains "$nushell_config_path" '$env.config.show_banner = false' 'preserves existing Nushell config content'
}

test_uses_xdg_config_home_for_nushell_when_set() {
  local temp_dir
  local output_file
  local xdg_config_home
  local xdg_nushell_config
  local default_nushell_config

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  xdg_config_home="$temp_dir/xdg-config"
  xdg_nushell_config="$xdg_config_home/nushell/config.nu"
  default_nushell_config="$(canonical_nushell_config_path "$temp_dir/home")"
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

  if ! XDG_CONFIG_HOME="$xdg_config_home" run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should use XDG config home for Nushell when set'
  fi

  assert_contains "$xdg_nushell_config" 'let brew_bin =' 'writes Nushell config to XDG config home'
  [[ ! -e "$default_nushell_config" ]] || fail 'should not create default macOS Nushell config when XDG_CONFIG_HOME is set'
  [[ ! -e "$(macos_nushell_compatibility_dir "$temp_dir/home")" ]] || fail 'should not manage macOS Nushell compatibility symlink when XDG_CONFIG_HOME is set'
}

test_uses_linux_default_nushell_path() {
  local temp_dir
  local output_file
  local home_path
  local nushell_config_path

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  home_path="$temp_dir/home"
  nushell_config_path="$(linux_nushell_config_path "$home_path")"
  mkdir -p "$temp_dir/state" "$temp_dir/configs/linux/brew"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/linux/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  if ! TEST_UNAME=Linux run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should use the Linux default Nushell config path'
  fi

  assert_contains "$nushell_config_path" 'let brew_bin =' 'writes Nushell config to Linux default path'
}

test_accepts_bash_profile_sourcing_bashrc() {
  local temp_dir
  local output_file
  local home_path

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  home_path="$temp_dir/home"
  mkdir -p "$temp_dir/state" "$home_path"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$home_path/.bash_profile" <<'EOF'
if [[ -f ~/.bashrc ]]; then
  . ~/.bashrc
fi
EOF

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should tolerate bash profile sourcing bashrc'
  fi

  assert_contains "$home_path/.bash_profile" '. ~/.bashrc' 'preserves bash profile sourcing bashrc'
  assert_contains "$home_path/.bash_profile" 'brew shellenv bash' 'adds shellenv to bash profile'
  assert_contains "$home_path/.bashrc" 'brew shellenv bash' 'adds shellenv to bashrc'
}

test_nushell_block_guards_against_duplicate_paths() {
  local temp_dir
  local output_file
  local nushell_config_path

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  nushell_config_path="$(canonical_nushell_config_path "$temp_dir/home")"
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

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should write a guarded Nushell PATH block'
  fi

  assert_contains "$nushell_config_path" 'if ($env.PATH | describe | str starts-with "list<") {' 'guards Nushell block against unexpected PATH type'
  assert_occurrences "$nushell_config_path" 'not-in $env.PATH' 2 'checks both Nushell Homebrew paths before prepend'
}

test_ignores_inherited_mkdir_shell_function() {
  local temp_dir
  local output_file

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  mkdir -p "$temp_dir/state"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"

  trap 'rm -rf "$temp_dir"; unset -f mkdir 2>/dev/null || true' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  mkdir() {
    printf 'wrapped mkdir should not run\n' >&2
    return 99
  }

  export -f mkdir

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should ignore inherited mkdir shell functions'
  fi

  unset -f mkdir
}

test_creates_macos_nushell_compatibility_symlink() {
  local temp_dir
  local output_file
  local home_path
  local canonical_config_path
  local compatibility_dir

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  home_path="$temp_dir/home"
  canonical_config_path="$(canonical_nushell_config_path "$home_path")"
  compatibility_dir="$(macos_nushell_compatibility_dir "$home_path")"
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

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should create the macOS Nushell compatibility symlink'
  fi

  [[ -L "$compatibility_dir" ]] || fail 'should create the macOS Nushell compatibility symlink'
  [[ "$(readlink "$compatibility_dir")" == "$home_path/.config/nushell" ]] || fail 'compatibility symlink should point to the canonical Nushell dir'
  assert_contains "$canonical_config_path" 'let brew_bin =' 'writes canonical Nushell config when creating the compatibility symlink'
}

test_corrects_wrong_macos_nushell_symlink_target() {
  local temp_dir
  local output_file
  local home_path
  local compatibility_dir
  local wrong_target
  local canonical_config_path
  local stray_warning_path

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  home_path="$temp_dir/home"
  compatibility_dir="$(macos_nushell_compatibility_dir "$home_path")"
  wrong_target="$home_path/elsewhere/nushell"
  canonical_config_path="$(canonical_nushell_config_path "$home_path")"
  stray_warning_path="$temp_dir/WARNING: Corrected Nushell compatibility symlink to point to $home_path/.config/nushell"
  mkdir -p "$temp_dir/state" "$wrong_target" "$(dirname "$compatibility_dir")"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"
  ln -s "$wrong_target" "$compatibility_dir"
  printf '# migrated file\n' > "$wrong_target/env.nu"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should correct a wrong macOS Nushell symlink target'
  fi

  [[ "$(readlink "$compatibility_dir")" == "$home_path/.config/nushell" ]] || fail 'should correct the macOS Nushell symlink target'
  assert_contains "$home_path/.config/nushell/env.nu" '# migrated file' 'migrates non-conflicting files from the wrong symlink target'
  assert_contains "$canonical_config_path" 'let brew_bin =' 'writes managed config after correcting the symlink'
  assert_contains "$output_file" 'WARNING: Corrected Nushell compatibility symlink to point to ' 'reports the corrected macOS Nushell symlink'
  assert_path_missing "$stray_warning_path" 'should not create a stray warning-named file when correcting the symlink'
}

test_migrates_macos_nushell_directory_to_canonical_config_dir() {
  local temp_dir
  local output_file
  local home_path
  local compatibility_dir
  local canonical_config_path

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  home_path="$temp_dir/home"
  compatibility_dir="$(macos_nushell_compatibility_dir "$home_path")"
  canonical_config_path="$(canonical_nushell_config_path "$home_path")"
  mkdir -p "$temp_dir/state" "$compatibility_dir"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"
  printf '# migrated from compatibility dir\n' > "$compatibility_dir/env.nu"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  if ! run_in_fake_repo "$temp_dir" "$output_file"; then
    cat "$output_file" >&2
    fail 'script should migrate the macOS Nushell compatibility directory into the canonical dir'
  fi

  [[ -L "$compatibility_dir" ]] || fail 'should replace the compatibility directory with a symlink'
  assert_contains "$home_path/.config/nushell/env.nu" '# migrated from compatibility dir' 'migrates non-conflicting files from the compatibility directory'
  assert_contains "$canonical_config_path" 'let brew_bin =' 'writes managed config after directory migration'
}

test_fails_on_conflicting_macos_nushell_configs() {
  local temp_dir
  local output_file
  local home_path
  local compatibility_dir
  local canonical_dir

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/output.log"
  home_path="$temp_dir/home"
  compatibility_dir="$(macos_nushell_compatibility_dir "$home_path")"
  canonical_dir="$home_path/.config/nushell"
  mkdir -p "$temp_dir/state" "$compatibility_dir" "$canonical_dir"
  : > "$temp_dir/state/installed-formulae"
  : > "$temp_dir/state/installed-casks"
  printf '# canonical config\n' > "$canonical_dir/config.nu"
  printf '# conflicting compatibility config\n' > "$compatibility_dir/config.nu"

  trap 'rm -rf "$temp_dir"' RETURN

  make_fake_repo "$temp_dir"
  setup_common_stubs "$temp_dir"
  setup_brew_stub "$temp_dir"

  cat > "$temp_dir/configs/macos/brew/Brewfile-shared-ezirius" <<'EOF'
brew "nushell"
EOF

  if run_in_fake_repo "$temp_dir" "$output_file"; then
    fail 'script should fail when macOS Nushell config locations conflict'
  fi

  assert_contains "$output_file" 'ERROR: Conflicting Nushell config exists in both canonical and macOS compatibility locations. Resolve manually.' 'fails clearly on conflicting macOS Nushell config locations'
}

test_active_shell_files_pass_bash_syntax_check() {
  bash -n "$ROOT/libs/shared/shared/common.sh" || fail 'common.sh should pass bash -n'
  bash -n "$ROOT/scripts/shared/brew/brew-install" || fail 'brew-install should pass bash -n'
  bash -n "$ROOT/scripts/shared/shared/bootstrap" || fail 'bootstrap should pass bash -n'
  bash -n "$ROOT/scripts/macos/downloads/macos-download" || fail 'macos-download should pass bash -n'
  bash -n "$ROOT/scripts/macos/system/system-configure" || fail 'system-configure should pass bash -n'
}

test_selects_layered_brewfiles_and_installs_missing_only
test_warns_for_already_installed_configured_item_in_matched_brewfiles
test_warns_for_newly_installed_configured_item_in_matched_brewfiles
test_does_not_warn_for_configured_item_not_in_matched_brewfiles
test_does_not_warn_for_non_configured_item_even_if_installed
test_does_not_print_warning_heading_when_no_relevant_warning_items_exist
test_warn_matching_is_type_agnostic
test_fails_clearly_when_missing_cask_user_is_not_admin
test_skips_installed_cask_without_admin_failure
test_missing_formula_still_installs_without_admin_guard
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
test_bootstraps_homebrew_interactively_when_tty_is_available
test_bootstraps_homebrew_non_interactively_when_tty_is_unavailable
test_fails_clearly_when_homebrew_missing_and_user_is_not_admin
test_fails_clearly_when_non_interactive_homebrew_bootstrap_needs_sudo
test_supports_shared_shared_brewfile
test_supports_host_shared_brewfile
test_current_real_style_brewfiles_still_work
test_fails_clearly_when_bootstrap_curl_is_missing
test_requires_brew_installer_config_file
test_requires_brew_installer_values_from_config_file
test_requires_local_network_warning_values_from_config_file
test_handles_multiline_brew_version_output
test_requires_logging_values_from_config_file
test_persists_shell_setup_when_brew_exists
test_persists_shell_setup_after_homebrew_bootstrap
test_shell_setup_is_idempotent_on_rerun
test_preserves_existing_shell_config_content
test_uses_xdg_config_home_for_nushell_when_set
test_uses_linux_default_nushell_path
test_accepts_bash_profile_sourcing_bashrc
test_nushell_block_guards_against_duplicate_paths
test_ignores_inherited_mkdir_shell_function
test_creates_macos_nushell_compatibility_symlink
test_corrects_wrong_macos_nushell_symlink_target
test_migrates_macos_nushell_directory_to_canonical_config_dir
test_fails_on_conflicting_macos_nushell_configs
test_active_shell_files_pass_bash_syntax_check

printf 'PASS: tests/shared/brew/test-brew-install.sh\n'
