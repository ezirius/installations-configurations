#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
MOCK_BIN="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"
BREW_PREFIX="$TMPDIR/homebrew"
SCRIPT_FILE="$REPO_DIR/scripts/macos/brew-upgrade"
mkdir -p "$MOCK_BIN" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$BREW_PREFIX"
mkdir -p "$REPO_DIR/scripts/macos" "$REPO_DIR/lib/shell" "$REPO_DIR/config/brew"
trap 'rm -rf "$TMPDIR"' EXIT

cp "$ROOT/scripts/macos/brew-upgrade" "$REPO_DIR/scripts/macos/brew-upgrade"
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
  list) exit 1 ;;
  update)
    if [[ -f "\$STATE_DIR/up-to-date" ]]; then
      printf 'Already up-to-date.\n'
    else
      printf 'Updated 1 tap (homebrew/core).\n'
    fi
    ;;
  bundle)
    printf '%s\n' "\$*" >> "\$STATE_DIR/brew.log"
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
touch "$STATE_DIR/outdated-formula-caddy" "$STATE_DIR/outdated-cask-ghostty"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$BREWFILE" >/dev/null
LOG_FILE="$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers/Maldoria Installations and Configurations-$(date '+%Y%m%d')---------.csv"
assert_contains "$LOG_FILE" 'Homebrew metadata' 'brew-upgrade logs metadata updates when update changes state'
assert_contains "$STATE_DIR/brew.log" 'upgrade caddy' 'brew-upgrade upgrades outdated formulae'
assert_contains "$STATE_DIR/brew.log" 'upgrade --cask ghostty' 'brew-upgrade upgrades outdated casks'

STATE_DIR="$TMPDIR/state-up-to-date"
mkdir -p "$STATE_DIR"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$BREWFILE" >/dev/null

echo "Brew upgrade runtime checks passed"
