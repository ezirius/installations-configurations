#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
MOCK_BIN="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"
BREW_PREFIX="$TMPDIR/homebrew"
SCRIPT_FILE="$REPO_DIR/scripts/macos/brew-install"
mkdir -p "$MOCK_BIN" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$BREW_PREFIX"
mkdir -p "$REPO_DIR/scripts/macos" "$REPO_DIR/lib/shell" "$REPO_DIR/config/brew" "$REPO_DIR/config/repo" "$REPO_DIR/config/podman"
trap 'rm -rf "$TMPDIR"' EXIT

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
cat > "$MOCK_BIN/python3" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/python3 "$@"
EOF
cat > "$MOCK_BIN/brew" <<EOF
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="\${STATE_DIR:?}"
case "\$1" in
  shellenv) ;;
  --prefix) printf '%s\n' "$BREW_PREFIX" ;;
  list)
    if [[ "\$2" == --versions ]]; then
      [[ -f "\$STATE_DIR/installed-formula-\$3" ]] && printf '%s 1.0.0\n' "\$3" || exit 1
    elif [[ "\$2" == --cask && "\$3" == --versions ]]; then
      [[ -f "\$STATE_DIR/installed-cask-\$4" ]] && printf '%s 1.0.0\n' "\$4" || exit 1
    fi
    ;;
  install)
    printf '%s\n' "\$*" >> "\$STATE_DIR/brew.log"
    if [[ "\$2" == --cask ]]; then
      : > "\$STATE_DIR/installed-cask-\$3"
    else
      : > "\$STATE_DIR/installed-formula-\$2"
    fi
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/scutil" "$MOCK_BIN/xcode-select" "$MOCK_BIN/python3" "$MOCK_BIN/brew"

BREWFILE="$TMPDIR/Brewfile"
cat > "$BREWFILE" <<'EOF'
brew "podman"
brew "podman-compose"
cask "podman-desktop"
EOF

STATE_DIR="$TMPDIR/state-idempotent"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/installed-formula-caddy" "$STATE_DIR/installed-cask-ghostty"
touch "$STATE_DIR/installed-formula-podman" "$STATE_DIR/installed-formula-podman-compose" "$STATE_DIR/installed-cask-podman-desktop"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$BREWFILE" >/dev/null
if [[ -f "$STATE_DIR/brew.log" ]]; then
  printf 'assertion failed: brew-install should not run install commands when entries already exist\n' >&2
  exit 1
fi

STATE_DIR="$TMPDIR/state-install"
mkdir -p "$STATE_DIR"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$BREWFILE" >/dev/null
assert_contains "$STATE_DIR/brew.log" 'install podman' 'brew-install installs missing formulae from the Brewfile'
assert_contains "$STATE_DIR/brew.log" 'install podman-compose' 'brew-install installs all missing Brewfile formulae'
assert_contains "$STATE_DIR/brew.log" 'install --cask podman-desktop' 'brew-install installs missing casks from the Brewfile'

STATE_DIR="$TMPDIR/state-missing-brewfile"
mkdir -p "$STATE_DIR"
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$TMPDIR/missing.Brewfile" >"$STATE_DIR/out" 2>"$STATE_DIR/err"; then
  printf 'assertion failed: brew-install should fail for a missing Brewfile\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/err" 'Brewfile not found' 'brew-install reports a missing Brewfile clearly'

echo "Brewfile runtime checks passed"
