#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
COMMON_FILE="$ROOT/lib/shell/shared/common.sh"
BREW_HELPERS_FILE="$ROOT/lib/shell/shared/homebrew.sh"
MACHINE_CONFIG_HELPERS_FILE="$ROOT/lib/shell/shared/machine-config.sh"
TMPDIR="$(mktemp -d)"
HOST_PYTHON3="$(command -v python3)"
trap 'rm -rf "$TMPDIR"' EXIT

test -f "$COMMON_FILE"
test -f "$BREW_HELPERS_FILE"
test -f "$MACHINE_CONFIG_HELPERS_FILE"

mkdir -p "$TMPDIR/bin"

cat > "$TMPDIR/bin/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF

cat > "$TMPDIR/bin/scutil" <<'EOF'
#!/usr/bin/env bash
printf 'My Maldoria.local!!\n'
EOF

cat > "$TMPDIR/bin/hostname" <<'EOF'
#!/usr/bin/env bash
printf 'IgnoredHost\n'
EOF

cat > "$TMPDIR/bin/python3" <<EOF
#!/usr/bin/env bash
exec "$HOST_PYTHON3" "\$@"
EOF

chmod +x "$TMPDIR/bin/uname" "$TMPDIR/bin/scutil" "$TMPDIR/bin/hostname" "$TMPDIR/bin/python3"

PATH="$TMPDIR/bin:$PATH" ROOT="$ROOT" bash -c '
  source "$ROOT/lib/shell/shared/common.sh"
  source "$ROOT/lib/shell/shared/homebrew.sh"
  source "$ROOT/lib/shell/shared/machine-config.sh"
  test "$(raw_host_name)" = "My Maldoria"
  test "$(normalize_name "My Maldoria.local!!")" = "my-maldoria-local"
  test "$(normalized_host_name)" = "my-maldoria"
  test "$(detect_log_host_name)" = "My Maldoria"
  test "$(shared_repo_config_path "config/example" "example-settings" "conf")" = "$ROOT/config/example/shared/example-settings-shared.conf"
  test "$(shared_platform_config_path "config/brew" "brew-packages" "Brewfile")" = "$ROOT/config/brew/macos/brew-packages-shared.Brewfile"
  test "$(host_platform_config_path "config/brew" "brew-packages" "Brewfile")" = "$ROOT/config/brew/macos/brew-packages-my-maldoria.Brewfile"
'

if PATH="$TMPDIR/bin:$PATH" ROOT="$ROOT" bash -c 'source "$ROOT/lib/shell/shared/common.sh"; shared_platform_config_path "config/brew" "Brewfile"' >/dev/null 2>&1; then
  printf 'assertion failed: shared_platform_config_path should require an explicit filejob\n' >&2
  exit 1
fi

rm "$TMPDIR/bin/scutil"
PATH="$TMPDIR/bin:$PATH" ROOT="$ROOT" bash -c '
  source "$ROOT/lib/shell/shared/common.sh"
  source "$ROOT/lib/shell/shared/homebrew.sh"
  source "$ROOT/lib/shell/shared/machine-config.sh"
  test "$(raw_host_name)" = "IgnoredHost"
  test "$(normalized_host_name)" = "ignoredhost"
  test "$(detect_log_host_name)" = "IgnoredHost"
'

cat > "$TMPDIR/bin/hostname" <<'EOF'
#!/usr/bin/env bash
printf 'Slash/Host\n'
EOF
chmod +x "$TMPDIR/bin/hostname"
PATH="$TMPDIR/bin:$PATH" ROOT="$ROOT" bash -c '
  source "$ROOT/lib/shell/shared/common.sh"
  source "$ROOT/lib/shell/shared/homebrew.sh"
  test "$(safe_log_host_name)" = "Slash-Host"
'

cat > "$TMPDIR/machine.conf" <<'EOF'
[machine]
token=100% literal
EOF

PATH="$TMPDIR/bin:$PATH" ROOT="$ROOT" bash -c '
  source "$ROOT/lib/shell/shared/common.sh"
  source "$ROOT/lib/shell/shared/homebrew.sh"
  source "$ROOT/lib/shell/shared/machine-config.sh"
  test "$(read_machine_config_value "'$TMPDIR'/machine.conf" token)" = "100% literal"
'

cat > "$TMPDIR/Brewfile" <<'EOF'
brew "wget"
cask "ghostty"
EOF

cat > "$TMPDIR/bin/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
  '--prefix')
    printf '/opt/homebrew\n'
    ;;
  'list --versions wget')
    printf 'wget 1.0\n'
    ;;
  'list --cask --versions ghostty')
    printf 'ghostty 2.0\n'
    ;;
  'list --versions ghostty'|'list --cask --versions wget')
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
EOF

chmod +x "$TMPDIR/bin/brew"

PATH="$TMPDIR/bin:$PATH" ROOT="$ROOT" bash -c '
  source "$ROOT/lib/shell/shared/common.sh"
  source "$ROOT/lib/shell/shared/homebrew.sh"

  entries_file="'$TMPDIR'/entries.txt"
  before_file="'$TMPDIR'/before.txt"
  after_file="'$TMPDIR'/after.txt"
  install_before_file="'$TMPDIR'/install-before.txt"
  install_after_file="'$TMPDIR'/install-after.txt"
  invalid_entries_file="'$TMPDIR'/invalid-entries.txt"
  missing_output="'$TMPDIR'/missing.err"
  invalid_entry_output="'$TMPDIR'/invalid-entry.err"
  paths_file="'$TMPDIR'/paths.txt"
  override_file="'$TMPDIR'/override.Brewfile"
  shared_brewfile="$(shared_platform_config_path "config/brew" "brew-packages" "Brewfile")"
  host_brewfile="$(host_platform_config_path "config/brew" "brew-packages" "Brewfile")"

  write_brewfile_entries "'$TMPDIR'/Brewfile" "$entries_file"
  test "$(cat "$entries_file")" = "brew|wget
cask|ghostty"

  if write_brewfile_entries "'$TMPDIR'/missing.Brewfile" "$entries_file" > /dev/null 2>"$missing_output"; then
    printf "assertion failed: write_brewfile_entries should fail for a missing Brewfile\n" >&2
    exit 1
  fi
  test -s "$missing_output"

  collected_entries=""
  collect_entry() {
    collected_entries+="$1|$2\n"
  }
  for_each_brew_entry "$entries_file" collect_entry
  test "$collected_entries" = "brew|wget\ncask|ghostty\n"

  snapshot_brew_entries_state "$entries_file" "$before_file"
  test "$(cat "$before_file")" = "brew|wget|installed|wget 1.0
cask|ghostty|installed|ghostty 2.0"

  cat > "$after_file" <<'"'"'EOF'"'"'
brew|wget|installed|wget 1.1
cask|ghostty|missing|
EOF

  cat > "$install_before_file" <<'"'"'EOF'"'"'
brew|wget|missing|
cask|ghostty|installed|ghostty 2.0
EOF

  cat > "$install_after_file" <<'"'"'EOF'"'"'
brew|wget|installed|wget 1.0
cask|ghostty|installed|ghostty 2.0
EOF

  declare -F report_brew_install_state_changes >/dev/null
  declare -F report_brew_upgrade_state_changes >/dev/null
  test "$(report_brew_install_state_changes "$install_before_file" "$install_after_file" "'$HOST_PYTHON3'")" = "brew|wget|Installed"
  test "$(report_brew_upgrade_state_changes "$before_file" "$after_file" "'$HOST_PYTHON3'")" = "wget|Upgraded"

  cat > "$invalid_entries_file" <<'"'"'EOF'"'"'
mas|xcode
EOF

  if snapshot_brew_entries_state "$invalid_entries_file" "$before_file" > /dev/null 2>"$invalid_entry_output"; then
    printf "assertion failed: snapshot_brew_entries_state should fail for unsupported entry types\n" >&2
    exit 1
  fi
  test -s "$invalid_entry_output"

  : > "$paths_file"
  collect_path() {
    printf "%s\n" "$1" >> "$paths_file"
  }

  rm -f "$host_brewfile"
  for_each_managed_brewfile collect_path
  test "$(cat "$paths_file")" = "$shared_brewfile"

  : > "$paths_file"
  : > "$host_brewfile"
  for_each_managed_brewfile collect_path
  test "$(cat "$paths_file")" = "$host_brewfile"

  : > "$override_file"
  : > "$paths_file"
  for_each_managed_brewfile collect_path "$override_file"
  test "$(cat "$paths_file")" = "$override_file"

  rm -f "$host_brewfile"
'

echo "Common helper checks passed"
