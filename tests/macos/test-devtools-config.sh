#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/devtools-configure"

test -f "$SCRIPT_FILE"
test -f "$ROOT/config/fd/ignore"
test -f "$ROOT/config/bat/config"
test -f "$ROOT/config/eza/theme.yml"
test -f "$ROOT/config/tlrc/config.toml"
test -f "$ROOT/config/micro/settings.json"
test -f "$ROOT/config/micro/colorschemes/installations-configurations.micro"
test -f "$ROOT/config/vim/vimrc"
test -f "$ROOT/config/vim/colors/installations-configurations.vim"
test -f "$ROOT/config/starship/starship.toml"
test -f "$ROOT/config/zellij/config.kdl"
test -f "$ROOT/config/atuin/config.toml"
test -f "$ROOT/config/btop/btop.conf"
test -f "$ROOT/config/btop/themes/tokyo-night.theme"
test -f "$ROOT/config/lazygit/config.yml"
grep -q '^copy_managed_file() {$' "$SCRIPT_FILE"
grep -q '^ensure_bridge_file() {$' "$SCRIPT_FILE"
grep -q '^ensure_compat_symlink() {$' "$SCRIPT_FILE"
grep -q '^deploy_tree() {$' "$SCRIPT_FILE"

echo "Devtools config checks passed"
