#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

export HOME="$WORKDIR/home"
mkdir -p "$HOME"

source "$ROOT/lib/shell/common.sh"

INSTALLATIONS_CONFIGURATIONS_LOG_DIR="$HOME/Documents/Ezirius/Systems/Installations and Configurations/Computers"
HOST_NAME="$(detect_log_host_name)"
OPEN_LOG="$INSTALLATIONS_CONFIGURATIONS_LOG_DIR/$HOST_NAME Installations and Configurations-20260322---------.csv"
CLOSED_LOG="$INSTALLATIONS_CONFIGURATIONS_LOG_DIR/$HOST_NAME Installations and Configurations-20260320-20260321.csv"

mkdir -p "$INSTALLATIONS_CONFIGURATIONS_LOG_DIR"

initialize_change_log "scripts/macos/test-logging"
test -f "$INSTALLATIONS_CONFIGURATIONS_LOG_FILE"
grep -q '^Date,Time,Username,Type,Script,Item,Change,Path,Details$' "$INSTALLATIONS_CONFIGURATIONS_LOG_FILE"

log_change "Configuration" "CSV sample" "Created" "$HOME/sample" 'created "sample", with commas'
grep -q '"created ""sample"", with commas"$' "$INSTALLATIONS_CONFIGURATIONS_LOG_FILE"

printf '%s\n' 'Date,Time,Username,Type,Script,Item,Change,Path,Details' > "$OPEN_LOG"
initialize_change_log "scripts/macos/test-logging"
test "$INSTALLATIONS_CONFIGURATIONS_LOG_FILE" = "$OPEN_LOG"

rm -f "$OPEN_LOG"
touch "$CLOSED_LOG"
initialize_change_log "scripts/macos/test-logging"
test "$INSTALLATIONS_CONFIGURATIONS_LOG_FILE" != "$CLOSED_LOG"
test -f "$INSTALLATIONS_CONFIGURATIONS_LOG_FILE"

grep -q '^initialize_change_log "scripts/macos/brew-install"$' "$ROOT/scripts/macos/brew-install"
grep -q '^initialize_change_log "scripts/macos/brewfile-install"$' "$ROOT/scripts/macos/brewfile-install"
grep -q '^initialize_change_log "scripts/macos/brew-upgrade"$' "$ROOT/scripts/macos/brew-upgrade"
grep -q '^initialize_change_log "scripts/macos/git-configure"$' "$ROOT/scripts/macos/git-configure"
grep -q '^initialize_change_log "scripts/macos/iterm2-configure"$' "$ROOT/scripts/macos/iterm2-configure"
grep -q '^initialize_change_log "scripts/macos/podman-machine-install"$' "$ROOT/scripts/macos/podman-machine-install"
! grep -q '^initialize_change_log ' "$ROOT/scripts/macos/bootstrap"
! grep -q '^initialize_change_log ' "$ROOT/scripts/macos/podman-check"

grep -q '^log_change "Installation" "Homebrew" "Installed" "\$BREW_ROOT" "Installed Homebrew"$' "$ROOT/scripts/macos/brew-install"
grep -q '^    log_change "Installation" "\$entry_name" "\$change_name" "\$BREW_PREFIX" "Managed by Brewfile"$' "$ROOT/scripts/macos/brewfile-install"
grep -q '^  log_change "Installation" "Homebrew metadata" "Updated" "\$BREW_PREFIX" "Updated Homebrew metadata"$' "$ROOT/scripts/macos/brew-upgrade"
grep -q '^  log_change "Installation" "\$entry_name" "\$change_name" "\$BREW_PREFIX" "Managed by Brewfile upgrade"$' "$ROOT/scripts/macos/brew-upgrade"
grep -q '^    log_change "Configuration" "Git identity" "Updated" "\$gitconfig_path" "Configured global Git identity and default branch"$' "$ROOT/scripts/macos/git-configure"
grep -q '^    log_change "Configuration" "SSH config" "\$LAST_FILE_CHANGE" "\$SSH_CONFIG_PATH" "Managed GitHub SSH alias \$GITHUB_HOST_ALIAS"$' "$ROOT/scripts/macos/git-configure"
grep -q '^    log_change "Configuration" "Git remote" "\$change_name" "\$repo_git_config" "Set origin to \$TARGET_REMOTE_URL"$' "$ROOT/scripts/macos/git-configure"
grep -q '^  log_change "Configuration" "iTerm2 \$key" "\$change_name" "\$ITERM_PREFS_PATH" "Set \$key=\$desired_value"$' "$ROOT/scripts/macos/iterm2-configure"
grep -q '^  log_change "Configuration" "containers.conf" "Copied" "\$CONTAINERS_CONF_TARGET" "Copied Podman machine settings from repository"$' "$ROOT/scripts/macos/podman-machine-install"
grep -q '^  log_change "Configuration" "Podman machine" "Created" "\$MACHINE_STORAGE_PATH" "Created machine \$MACHINE_NAME"$' "$ROOT/scripts/macos/podman-machine-install"
grep -q '^    log_change "Configuration" "Podman machine" "Updated" "\$MACHINE_STORAGE_PATH" "Updated machine \$MACHINE_NAME settings"$' "$ROOT/scripts/macos/podman-machine-install"

echo "Logging checks passed"
