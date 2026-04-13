#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
MOCK_BIN="$TMPDIR/bin"
NO_BREW_BIN="$TMPDIR/no-brew-bin"
SCRIPT_FILE="$REPO_DIR/scripts/macos/brew-install"
mkdir -p "$MOCK_BIN" "$NO_BREW_BIN" "$REPO_DIR/scripts/macos" "$REPO_DIR/lib/shell" "$REPO_DIR/config/brew"
trap 'rm -rf "$TMPDIR"' EXIT

cp "$ROOT/scripts/macos/brew-install" "$REPO_DIR/scripts/macos/brew-install"
cp "$ROOT/lib/shell/common.sh" "$REPO_DIR/lib/shell/common.sh"
cp "$ROOT/config/brew/shared-macos.Brewfile" "$REPO_DIR/config/brew/shared-macos.Brewfile"
chmod +x "$SCRIPT_FILE"

git -C "$REPO_DIR" init -b main >/dev/null
git -C "$REPO_DIR" config user.name 'Repo User'
git -C "$REPO_DIR" config user.email 'repo.user@example.invalid'
git -C "$REPO_DIR" add . >/dev/null
git -C "$REPO_DIR" commit -m 'Initial' >/dev/null
git -C "$REPO_DIR" init --bare "$TMPDIR/remote.git" >/dev/null
git -C "$REPO_DIR" remote add origin "$TMPDIR/remote.git"
git -C "$REPO_DIR" push -u origin main >/dev/null 2>&1

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

cat > "$MOCK_BIN/xcode-select" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == -p ]]; then
  if [[ -f "$STATE_DIR/clt.installed" ]]; then
    printf '/Library/Developer/CommandLineTools\n'
    exit 0
  fi
  exit 1
fi

if [[ "$1" == --install ]]; then
  printf 'install requested\n' >> "$STATE_DIR/xcode-select.log"
  exit 0
fi

exit 1
EOF

cat > "$MOCK_BIN/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
case "$1" in
  --version)
    printf 'Homebrew 4.0.0\n'
    ;;
  shellenv|--prefix)
    ;;
  list)
    if [[ "$2" == --versions ]]; then
      [[ -f "$STATE_DIR/installed-formula-$3" ]] && printf '%s 1.0.0\n' "$3" || exit 1
    elif [[ "$2" == --cask && "$3" == --versions ]]; then
      [[ -f "$STATE_DIR/installed-cask-$4" ]] && printf '%s 1.0.0\n' "$4" || exit 1
    fi
    ;;
  install)
    printf '%s\n' "$*" >> "$STATE_DIR/brew.log"
    if [[ "$2" == --cask ]]; then
      : > "$STATE_DIR/installed-cask-$3"
    else
      : > "$STATE_DIR/installed-formula-$2"
    fi
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/xcode-select" "$MOCK_BIN/brew"
cp "$MOCK_BIN/uname" "$NO_BREW_BIN/uname"
cp "$MOCK_BIN/xcode-select" "$NO_BREW_BIN/xcode-select"
chmod +x "$NO_BREW_BIN/uname" "$NO_BREW_BIN/xcode-select"

STATE_DIR="$TMPDIR/state-missing-clt"
mkdir -p "$STATE_DIR"
if PATH="$MOCK_BIN:$PATH" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >"$STATE_DIR/out" 2>"$STATE_DIR/err"; then
  printf 'assertion failed: brew-install should fail when CLT are missing\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/out" 'Triggering Apple installer' 'brew-install triggers CLT guidance when CLT are missing'
assert_contains "$STATE_DIR/xcode-select.log" 'install requested' 'brew-install invokes xcode-select --install'

STATE_DIR="$TMPDIR/state-brew-present"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/clt.installed"
mkdir -p "$TMPDIR/brew-present"
ln -sf "$MOCK_BIN/brew" "$TMPDIR/brew-present/brew"
if ! PATH="$TMPDIR/brew-present:$MOCK_BIN:$PATH" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >"$STATE_DIR/out" 2>"$STATE_DIR/err"; then
  printf 'assertion failed: brew-install should succeed when brew is already installed\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/out" 'Homebrew already installed' 'brew-install reports existing brew installation'

STATE_DIR="$TMPDIR/state-install"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/clt.installed"
cat > "$TMPDIR/Brewfile" <<'EOF'
brew "caddy"
cask "ghostty"
EOF
PATH="$TMPDIR/brew-present:$MOCK_BIN:$PATH" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$TMPDIR/Brewfile" >"$STATE_DIR/out" 2>"$STATE_DIR/err"
assert_contains "$STATE_DIR/brew.log" 'install caddy' 'brew-install installs missing formulae'
assert_contains "$STATE_DIR/brew.log" 'install --cask ghostty' 'brew-install installs missing casks'

STATE_DIR="$TMPDIR/state-no-upgrade"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/clt.installed" "$STATE_DIR/installed-formula-caddy" "$STATE_DIR/installed-cask-ghostty"
PATH="$TMPDIR/brew-present:$MOCK_BIN:$PATH" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$TMPDIR/Brewfile" >"$STATE_DIR/out" 2>"$STATE_DIR/err"
if [[ -f "$STATE_DIR/brew.log" ]]; then
  printf 'assertion failed: brew-install should not run installs for already installed entries\n' >&2
  exit 1
fi

STATE_DIR="$TMPDIR/state-manual"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/clt.installed"
if PATH="$NO_BREW_BIN:/usr/bin:/bin" STATE_DIR="$STATE_DIR" bash "$SCRIPT_FILE" >"$STATE_DIR/out" 2>"$STATE_DIR/err"; then
  printf 'assertion failed: brew-install should refuse unverifiable automatic install\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/err" 'does not execute the upstream Homebrew installer automatically' 'brew-install explains the manual-install requirement'

echo "Brew install runtime checks passed"
