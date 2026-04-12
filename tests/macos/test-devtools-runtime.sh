#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/devtools-configure"
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"
mkdir -p "$MOCK_BIN" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$HOME_DIR/.config"
trap 'rm -rf "$TMPDIR"' EXIT

assert_contains() {
  local file="$1" needle="$2" message="$3"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nmissing: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
cat > "$MOCK_BIN/scutil" <<'EOF'
#!/usr/bin/env bash
printf 'Maldoria\n'
EOF
cat > "$MOCK_BIN/xcode-select" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -p ]]
printf '/Library/Developer/CommandLineTools\n'
EOF
cat > "$MOCK_BIN/brew" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  shellenv) ;;
  --prefix) printf '/opt/homebrew\n' ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/scutil" "$MOCK_BIN/xcode-select" "$MOCK_BIN/brew"

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" "$SCRIPT_FILE" >/dev/null

assert_contains "$HOME_DIR/.config/fd/ignore" '.git/' 'fd ignore config deployed'
assert_contains "$HOME_DIR/.config/bat/config" '--theme="Nord"' 'bat config deployed'
assert_contains "$HOME_DIR/.config/eza/theme.yml" 'foreground: Blue' 'eza theme deployed'
assert_contains "$HOME_DIR/.config/tlrc/config.toml" 'bright_blue' 'tlrc config deployed'
assert_contains "$HOME_DIR/.config/starship/starship.toml" "palette = 'tokyo-night'" 'starship config deployed'
assert_contains "$HOME_DIR/.config/atuin/config.toml" 'search_mode = "fuzzy"' 'atuin config deployed'
assert_contains "$HOME_DIR/.config/btop/btop.conf" 'color_theme = "tokyo-night"' 'btop config deployed'
assert_contains "$HOME_DIR/.config/micro/settings.json" '"colorscheme": "installations-configurations"' 'micro config deployed'
assert_contains "$HOME_DIR/.config/vim/vimrc" 'colorscheme installations-configurations' 'vim config deployed'
assert_contains "$HOME_DIR/.config/vim/vimrc" 'set clipboard=unnamedplus' 'vim uses the system clipboard explicitly'
assert_contains "$HOME_DIR/.config/lazygit/config.yml" 'activeBorderColor:' 'lazygit config deployed'
assert_contains "$HOME_DIR/.vimrc" 'source ~/.config/vim/vimrc' 'vim bridge deployed'
if [[ ! -L "$HOME_DIR/Library/Application Support/lazygit" ]]; then
  printf 'assertion failed: lazygit compatibility path should be a symlink\n' >&2
  exit 1
fi
if [[ ! -L "$HOME_DIR/Library/Application Support/org.Zellij-Contributors.Zellij" ]]; then
  printf 'assertion failed: zellij compatibility path should be a symlink\n' >&2
  exit 1
fi

BROKEN_DIR="$TMPDIR/broken"
mkdir -p "$BROKEN_DIR/bin" "$BROKEN_DIR/home/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$BROKEN_DIR/home/.config" "$BROKEN_DIR/home/Library/Application Support/lazygit" "$BROKEN_DIR/home/Library/Application Support/org.Zellij-Contributors.Zellij"
cp "$MOCK_BIN/uname" "$BROKEN_DIR/bin/uname"
cp "$MOCK_BIN/scutil" "$BROKEN_DIR/bin/scutil"
cp "$MOCK_BIN/xcode-select" "$BROKEN_DIR/bin/xcode-select"
cp "$MOCK_BIN/brew" "$BROKEN_DIR/bin/brew"
chmod +x "$BROKEN_DIR/bin"/*
if PATH="$BROKEN_DIR/bin:$PATH" HOME="$BROKEN_DIR/home" XDG_CONFIG_HOME="$BROKEN_DIR/home/.config" "$SCRIPT_FILE" >"$BROKEN_DIR/out" 2>"$BROKEN_DIR/err"; then
  printf 'assertion failed: devtools-configure should fail when compatibility paths exist as unmanaged directories\n' >&2
  exit 1
fi
assert_contains "$BROKEN_DIR/err" 'compatibility path already exists and is not a symlink' 'devtools-configure protects unmanaged compatibility paths'

echo "Devtools runtime checks passed"
