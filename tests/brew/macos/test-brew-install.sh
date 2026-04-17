#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/brew/macos/brew-install"
CONFIG_FILE="$ROOT/config/brew/macos/brew-settings-shared.conf"
BREW_HELPERS_FILE="$ROOT/lib/shell/shared/homebrew.sh"

test -f "$SCRIPT_FILE"
test -f "$CONFIG_FILE"
test -f "$BREW_HELPERS_FILE"
grep -q '^BREW_INSTALL_REQUIRE_COMMITTED_REPO=true$' "$CONFIG_FILE"
grep -q '^BREW_INSTALL_TRIGGER_CLT_INSTALLER_IF_MISSING=true$' "$CONFIG_FILE"
grep -q '^BREW_INSTALL_ALLOW_HOMEBREW_AUTO_INSTALL=false$' "$CONFIG_FILE"
grep -q 'preferred_scoped_config_path "config/brew" "macos" "brew-settings" "conf"' "$SCRIPT_FILE"
! grep -q 'brew bundle install --file=' "$SCRIPT_FILE"

echo "Brew install checks passed"
