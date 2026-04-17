#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
MOCK_BIN="$TMPDIR/bin"
NO_BREW_BIN="$TMPDIR/no-brew-bin"
SCRIPT_FILE="$REPO_DIR/scripts/macos/brew-install"
HELPERS="$ROOT/lib/test/runtime-helpers.sh"
HOST_PYTHON3="$(command -v python3)"
mkdir -p "$MOCK_BIN" "$NO_BREW_BIN" "$REPO_DIR/scripts/macos" "$REPO_DIR/lib/shell" "$REPO_DIR/config/brew" "$REPO_DIR/config/repo" "$REPO_DIR/config/podman"
trap 'rm -rf "$TMPDIR"' EXIT
source "$HELPERS"

cp "$ROOT/scripts/macos/brew-install" "$REPO_DIR/scripts/macos/brew-install"
cp "$ROOT/lib/shell/common.sh" "$REPO_DIR/lib/shell/common.sh"
cp "$ROOT/config/brew/shared-macos.Brewfile" "$REPO_DIR/config/brew/shared-macos.Brewfile"
cp "$ROOT/config/repo/shared.conf" "$REPO_DIR/config/repo/shared.conf"
cp "$ROOT/config/podman/shared-macos.conf" "$REPO_DIR/config/podman/shared-macos.conf"
chmod +x "$SCRIPT_FILE"

git -C "$REPO_DIR" init -b main >/dev/null
git -C "$REPO_DIR" config user.name 'Repo User'
git -C "$REPO_DIR" config user.email 'repo.user@example.invalid'
git -C "$REPO_DIR" add . >/dev/null
git -C "$REPO_DIR" commit -m 'Initial' >/dev/null
git -C "$REPO_DIR" init --bare "$TMPDIR/remote.git" >/dev/null
git -C "$REPO_DIR" remote add origin "$TMPDIR/remote.git"
git -C "$REPO_DIR" push -u origin main >/dev/null 2>&1

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
cat > "$MOCK_BIN/python3" <<EOF
#!/usr/bin/env bash
exec "$HOST_PYTHON3" "\$@"
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/xcode-select" "$MOCK_BIN/brew" "$MOCK_BIN/python3"
cp "$MOCK_BIN/uname" "$NO_BREW_BIN/uname"
cp "$MOCK_BIN/xcode-select" "$NO_BREW_BIN/xcode-select"
chmod +x "$NO_BREW_BIN/uname" "$NO_BREW_BIN/xcode-select"

STATE_DIR="$TMPDIR/state-dirty-repo"
mkdir -p "$STATE_DIR"
touch "$REPO_DIR/dirty.txt"
if PATH="$MOCK_BIN:$PATH" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >"$STATE_DIR/out" 2>"$STATE_DIR/err"; then
  printf 'assertion failed: brew-install should fail when the repository has uncommitted changes\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/err" 'Repository has uncommitted changes. Commit and push before running brew-install.' 'brew-install reports dirty working trees through the safety gate'
rm -f "$REPO_DIR/dirty.txt"

STATE_DIR="$TMPDIR/state-no-upstream"
mkdir -p "$STATE_DIR"
git -C "$REPO_DIR" checkout -b local-only >/dev/null
if PATH="$MOCK_BIN:$PATH" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >"$STATE_DIR/out" 2>"$STATE_DIR/err"; then
  printf 'assertion failed: brew-install should fail when the current branch has no upstream\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/err" 'Current branch has no upstream. Push the branch before running brew-install.' 'brew-install reports missing upstream branches through the safety gate'
git -C "$REPO_DIR" checkout main >/dev/null

STATE_DIR="$TMPDIR/state-ahead-of-upstream"
mkdir -p "$STATE_DIR"
git -C "$REPO_DIR" checkout -b ahead origin/main >/dev/null
touch "$REPO_DIR/ahead.txt"
git -C "$REPO_DIR" add ahead.txt >/dev/null
git -C "$REPO_DIR" commit -m 'Ahead-only runtime test' >/dev/null
if PATH="$MOCK_BIN:$PATH" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >"$STATE_DIR/out" 2>"$STATE_DIR/err"; then
  printf 'assertion failed: brew-install should fail when the current branch has unpushed commits\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/err" 'Current branch has unpushed commits. Push before running brew-install.' 'brew-install reports branches ahead of upstream through the safety gate'
git -C "$REPO_DIR" checkout main >/dev/null

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
ln -sf "$MOCK_BIN/python3" "$TMPDIR/brew-present/python3"
if ! PATH="$TMPDIR/brew-present:$MOCK_BIN:$PATH" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >"$STATE_DIR/out" 2>"$STATE_DIR/err"; then
  printf 'assertion failed: brew-install should succeed when brew is already installed\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/out" 'Homebrew already installed' 'brew-install reports existing brew installation'

STATE_DIR="$TMPDIR/state-install"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/clt.installed"
cat > "$TMPDIR/Brewfile" <<'EOF'
brew 'caddy'
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
