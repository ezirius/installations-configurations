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
grep -q '^initialize_change_log "scripts/macos/brew-upgrade"$' "$ROOT/scripts/macos/brew-upgrade"
! grep -q '^initialize_change_log ' "$ROOT/scripts/macos/brew-configure"
! grep -q '^initialize_change_log ' "$ROOT/scripts/macos/brew-service"
grep -q '^initialize_change_log "scripts/macos/caddy-configure"$' "$ROOT/scripts/macos/caddy-configure"
grep -q '^initialize_change_log "scripts/macos/caddy-trust"$' "$ROOT/scripts/macos/caddy-trust"
grep -q '^initialize_change_log "scripts/macos/devtools-configure"$' "$ROOT/scripts/macos/devtools-configure"
grep -q '^initialize_change_log "scripts/macos/git-configure"$' "$ROOT/scripts/macos/git-configure"
grep -q '^initialize_change_log "scripts/macos/ghostty-configure"$' "$ROOT/scripts/macos/ghostty-configure"
grep -q '^initialize_change_log "scripts/macos/jj-configure"$' "$ROOT/scripts/macos/jj-configure"
grep -q '^initialize_change_log "scripts/macos/nushell-configure"$' "$ROOT/scripts/macos/nushell-configure"
grep -q '^initialize_change_log "scripts/macos/system-configure"$' "$ROOT/scripts/macos/system-configure"
grep -q '^initialize_change_log "scripts/macos/podman-configure"$' "$ROOT/scripts/macos/podman-configure"
! grep -q '^initialize_change_log ' "$ROOT/scripts/macos/bootstrap"
! grep -q '^initialize_change_log ' "$ROOT/scripts/macos/caddy-service"
! grep -q '^initialize_change_log ' "$ROOT/scripts/macos/podman-check"

grep -q 'log_change "Installation" "\$entry_name" "\$change_name" "\$BREW_PREFIX" "Managed by Brewfile"$' "$ROOT/scripts/macos/brew-install"
grep -q '^  log_change "Installation" "Homebrew metadata" "Updated" "\$BREW_PREFIX" "Updated Homebrew metadata"$' "$ROOT/scripts/macos/brew-upgrade"
grep -q 'log_change "Installation" "\$entry_name" "\$change_name" "\$BREW_PREFIX" "Managed by Brewfile upgrade"$' "$ROOT/scripts/macos/brew-upgrade"
grep -q '^  log_change "Configuration" "Caddyfile" "\$change_name" "\$target_path" "Deployed managed Caddy reverse proxy config"$' "$ROOT/scripts/macos/caddy-configure"
grep -q '^log_change "Configuration" "Caddy local CA" "Trusted" "\$TRUSTED_KEYCHAIN" "Trusted the managed Caddy local CA for local HTTPS"$' "$ROOT/scripts/macos/caddy-trust"
grep -q '^  log_change "Configuration" "Git managed include" "\$change_name" "\$MANAGED_GIT_CONFIG_PATH" "Updated the managed global Git defaults include"$' "$ROOT/scripts/macos/git-configure"
grep -q '^    log_change "Configuration" "Git identity" "Updated" "\$gitconfig_path" "Configured the global Git include for managed identity, editor, and review defaults"$' "$ROOT/scripts/macos/git-configure"
grep -q '^    log_change "Configuration" "SSH config" "\$LAST_FILE_CHANGE" "\$SSH_CONFIG_PATH" "Managed GitHub SSH alias \$GITHUB_HOST_ALIAS"$' "$ROOT/scripts/macos/git-configure"
grep -q '^    log_change "Configuration" "Git remote" "\$change_name" "\$repo_git_config" "Set origin to \$TARGET_REMOTE_URL"$' "$ROOT/scripts/macos/git-configure"
grep -q '^  log_change "Configuration" "Ghostty config" "\$change_name" "\$target_path" "Configured Ghostty to launch Nushell with the managed dark theme"$' "$ROOT/scripts/macos/ghostty-configure"
grep -q 'log_change "Configuration" "Ghostty config include" ' "$ROOT/scripts/macos/ghostty-configure"
grep -q '^  log_change "Configuration" "jj config" "\$change_name" "\$output_path" "Configured jj identity defaults"$' "$ROOT/scripts/macos/jj-configure"
grep -q '^  log_change "Configuration" "Nushell compatibility symlink" "\$change_name" "\$compat_path" "Linked macOS Application Support to the managed ~/.config/nushell tree"$' "$ROOT/scripts/macos/nushell-configure"
grep -q '^  log_change "Configuration" "lazygit compatibility symlink" "\$change_name" "\$compat_path" "Linked the macOS Lazygit config path to ~/.config/lazygit"$' "$ROOT/scripts/macos/devtools-configure"
grep -q '^  log_change "Configuration" "zellij compatibility symlink" "\$change_name" "\$compat_path" "Linked the macOS Zellij config path to ~/.config/zellij"$' "$ROOT/scripts/macos/devtools-configure"
grep -q '^set_dock_bool autohide "\$DOCK_AUTOHIDE" "Dock autohide"$' "$ROOT/scripts/macos/system-configure"
grep -q '^set_dock_bool mru-spaces "\$DOCK_MRU_SPACES" "Dock mru-spaces"$' "$ROOT/scripts/macos/system-configure"
grep -q '^  log_change "Configuration" "Power management" "Updated" "pmset" "Set \$scope_flag sleep \$desired_value to prevent automatic system sleep while on AC power"$' "$ROOT/scripts/macos/system-configure"
grep -q '^  log_change "Configuration" "containers.conf" "Copied" "\$CONTAINERS_CONF_TARGET" "Copied Podman machine settings from repository"$' "$ROOT/scripts/macos/podman-configure"
grep -q '^  log_change "Configuration" "Podman machine" "Created" "\$MACHINE_STORAGE_PATH" "Created machine \$MACHINE_NAME"$' "$ROOT/scripts/macos/podman-configure"
grep -q '^    log_change "Configuration" "Podman machine" "Updated" "\$MACHINE_STORAGE_PATH" "Updated machine \$MACHINE_NAME settings"$' "$ROOT/scripts/macos/podman-configure"

echo "Logging checks passed"
