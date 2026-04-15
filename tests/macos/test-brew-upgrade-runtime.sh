#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPERS="$ROOT/lib/test/runtime-helpers.sh"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
MOCK_BIN="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"
BREW_PREFIX="$TMPDIR/homebrew"
SCRIPT_FILE="$REPO_DIR/scripts/macos/brew-upgrade"
mkdir -p "$MOCK_BIN" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$BREW_PREFIX" "$REPO_DIR/scripts/macos" "$REPO_DIR/lib/shell" "$REPO_DIR/config/brew" "$REPO_DIR/config/repo" "$REPO_DIR/config/podman"
trap 'rm -rf "$TMPDIR"' EXIT
source "$HELPERS"

cp "$ROOT/scripts/macos/brew-upgrade" "$REPO_DIR/scripts/macos/brew-upgrade"
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
  update)
    if [[ -f "\$STATE_DIR/up-to-date" ]]; then
      printf 'Already up-to-date.\n'
    else
      printf 'Updated 1 tap (homebrew/core).\n'
    fi
    ;;
  outdated)
    if [[ "\$2" == --formula && -f "\$STATE_DIR/outdated-formula-\$3" ]]; then
      printf '%s\n' "\$3"
    elif [[ "\$2" == --cask && -f "\$STATE_DIR/outdated-cask-\$3" ]]; then
      printf '%s\n' "\$3"
    fi
    ;;
  upgrade)
    printf '%s\n' "\$*" >> "\$STATE_DIR/brew.log"
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/scutil" "$MOCK_BIN/xcode-select" "$MOCK_BIN/python3" "$MOCK_BIN/brew"

BREWFILE="$TMPDIR/Brewfile"
cat > "$BREWFILE" <<'EOF'
brew "caddy"
cask "ghostty"
EOF

STATE_DIR="$TMPDIR/state-updated"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/installed-formula-caddy" "$STATE_DIR/installed-cask-ghostty" "$STATE_DIR/outdated-formula-caddy" "$STATE_DIR/outdated-cask-ghostty"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$BREWFILE" >/dev/null
assert_contains "$STATE_DIR/brew.log" 'upgrade caddy' 'brew-upgrade upgrades outdated formulae'
assert_contains "$STATE_DIR/brew.log" 'upgrade --cask ghostty' 'brew-upgrade upgrades outdated casks'

HOST_BREWFILE="$REPO_DIR/config/brew/maldoria-macos.Brewfile"
cat > "$HOST_BREWFILE" <<'EOF'
brew "podman"
EOF
git -C "$REPO_DIR" add config/brew/maldoria-macos.Brewfile >/dev/null
git -C "$REPO_DIR" commit -m 'Add host brewfile for runtime test' >/dev/null
git -C "$REPO_DIR" push >/dev/null 2>&1
STATE_DIR="$TMPDIR/state-layered"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/installed-formula-caddy" "$STATE_DIR/installed-formula-podman" "$STATE_DIR/outdated-formula-caddy" "$STATE_DIR/outdated-formula-podman"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >/dev/null
assert_contains "$STATE_DIR/brew.log" 'upgrade caddy' 'brew-upgrade still upgrades shared Brewfile entries in default mode'
assert_contains "$STATE_DIR/brew.log" 'upgrade podman' 'brew-upgrade also upgrades host-specific Brewfile entries in default mode'

STATE_DIR="$TMPDIR/state-missing"
mkdir -p "$STATE_DIR"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$BREWFILE" >/dev/null
if [[ -f "$STATE_DIR/brew.log" ]]; then
  printf 'assertion failed: brew-upgrade should not install or upgrade missing entries\n' >&2
  exit 1
fi

STATE_DIR="$TMPDIR/state-up-to-date"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/installed-formula-caddy" "$STATE_DIR/installed-cask-ghostty" "$STATE_DIR/up-to-date"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$BREWFILE" >/dev/null
if [[ -f "$STATE_DIR/brew.log" ]]; then
  printf 'assertion failed: brew-upgrade should not run upgrades when entries are already current\n' >&2
  exit 1
fi

echo "Brew upgrade runtime checks passed"
